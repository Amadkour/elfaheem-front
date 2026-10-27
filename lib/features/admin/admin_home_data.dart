// lib/features/admin/admin_home_data.dart — the super admin's home over ONE payload (GET /api/v1/admin/overview,
// D-062), pure and unit-tested (test/org/admin_overview_test.dart).
//
//   AdminHomeData.fromOverview(json)   never throws: a block an older server lacks (`organizations`, `series`,
//                                      `alerts`, `realtime`) is simply absent — `hasOrganizations` / `hasSeries` /
//                                      `hasAlerts` / `hasRealtime` tell the body which tiles to hide.
//   AdminDayPoint                      one row of `series` (30 UTC days, oldest first).
//   AdminAlert                         one row of `alerts[]` (key, severity, count, deep link, extras).
//   halfDelta(values)                  the trend figure of a 30-day series: the last 15 days vs the 15 before, in
//                                      percent (null when the first half is 0 — nothing to compare against).
//
// The server sends exactly 30 rows, so "vs the previous period" means the previous HALF of the window; a true
// 30-vs-30 needs a 60-row series (open point in docs/polish/dashboards.md).
library;

import 'admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, asStr;

/// Percent change of the second half of [values] against the first half (null without a base).
double? halfDelta(List<double> values) {
  if (values.length < 2) return null;
  final mid = values.length ~/ 2;
  final a = values.take(mid).fold<double>(0, (s, v) => s + v);
  final b = values.skip(mid).fold<double>(0, (s, v) => s + v);
  if (a <= 0) return null;
  return (b - a) / a * 100;
}

class AdminDayPoint {
  const AdminDayPoint({
    required this.date,
    this.signups = 0,
    this.enrollments = 0,
    this.revenue = const {},
    this.liveSessions = 0,
    this.complaints = 0,
  });

  factory AdminDayPoint.fromJson(Map<String, dynamic> j) => AdminDayPoint(
        date: asStr(j['date']),
        signups: asInt(j['signups']),
        enrollments: asInt(j['enrollments']),
        revenue: asMap(j['revenue']).map((k, v) => MapEntry(k, asDouble(v))),
        liveSessions: asInt(j['live_sessions']),
        complaints: asInt(j['complaints']),
      );

  /// `YYYY-MM-DD` (a UTC day).
  final String date;
  final int signups, enrollments, liveSessions, complaints;

  /// Gross completed payments of the day, per currency.
  final Map<String, double> revenue;

  /// The day of the month as a short axis label ("07" → "7").
  String get dayLabel {
    final p = date.split('-');
    if (p.length != 3) return date;
    return '${int.tryParse(p[2]) ?? p[2]}';
  }

  double get revenueTotal => revenue.values.fold(0, (s, v) => s + v);
}

class AdminAlert {
  const AdminAlert({
    required this.key,
    required this.severity,
    required this.count,
    this.deepLink = '',
    this.byKind = const {},
    this.days,
  });

  factory AdminAlert.fromJson(Map<String, dynamic> j) => AdminAlert(
        key: asStr(j['key']),
        severity: asStr(j['severity'], 'info'),
        count: asInt(j['count']),
        deepLink: asStr(j['deep_link']),
        byKind: asMap(j['by_kind']).map((k, v) => MapEntry(k, asInt(v))),
        days: j['days'] == null ? null : asInt(j['days']),
      );

  final String key;

  /// danger | warning | info.
  final String severity;
  final int count;
  final String deepLink;

  /// `jobs_failed_24h`: failures per job kind.
  final Map<String, int> byKind;

  /// `payouts_overdue`: the age that makes a payout overdue.
  final int? days;

  bool get isDanger => severity == 'danger';
  bool get isWarning => severity == 'warning';
}

class AdminHomeData {
  const AdminHomeData({
    this.students = 0,
    this.teachers = 0,
    this.courses = 0,
    this.publishedCourses = 0,
    this.activeEnrollments = 0,
    this.pendingTransfers = 0,
    this.pendingSubscriptions = 0,
    this.activeSubscriptions = 0,
    this.subscriptionRequired = false,
    this.incomeByCurrency = const {},
    this.collectedByCurrency = const {},
    this.orgTotal,
    this.orgActive = 0,
    this.orgPendingApproval = 0,
    this.orgByType = const {},
    this.series = const [],
    this.hasAlerts = false,
    this.alerts = const [],
    this.hasRealtime = false,
    this.eventsLast24h,
  });

  /// Tolerant of every missing key: an empty map gives a home with every block hidden.
  factory AdminHomeData.fromOverview(Map<String, dynamic> j) {
    Map<String, double> money(String k) => asMap(j[k]).map((c, v) => MapEntry(c, asDouble(v)));
    final orgs = j['organizations'] is Map ? asMap(j['organizations']) : null;
    final rt = j['realtime'] is Map ? asMap(j['realtime']) : null;
    return AdminHomeData(
      students: asInt(j['students']),
      teachers: asInt(j['teachers']),
      courses: asInt(j['courses']),
      publishedCourses: asInt(j['published_courses']),
      activeEnrollments: asInt(j['active_enrollments']),
      pendingTransfers: asInt(j['pending_transfers']),
      pendingSubscriptions: asInt(j['pending_subscriptions']),
      activeSubscriptions: asInt(j['active_subscriptions']),
      subscriptionRequired: asBool(j['subscription_required']),
      incomeByCurrency: money('income_by_currency'),
      collectedByCurrency: money('collected_by_currency'),
      orgTotal: orgs == null ? null : asInt(orgs['total']),
      orgActive: orgs == null ? 0 : asInt(orgs['active']),
      orgPendingApproval: orgs == null ? 0 : asInt(orgs['pending_approval']),
      orgByType: orgs == null ? const {} : asMap(orgs['by_type']).map((k, v) => MapEntry(k, asInt(v))),
      series: [for (final r in asMapList(j['series'])) AdminDayPoint.fromJson(r)],
      hasAlerts: j['alerts'] is List,
      alerts: [for (final r in asMapList(j['alerts'])) AdminAlert.fromJson(r)],
      hasRealtime: rt != null,
      eventsLast24h: rt == null || rt['events_24h'] == null ? null : asInt(rt['events_24h']),
    );
  }

  // ── legacy keys (every server) ───────────────────────────────────────────
  final int students, teachers, courses, publishedCourses, activeEnrollments;
  final int pendingTransfers, pendingSubscriptions, activeSubscriptions;
  final bool subscriptionRequired;

  /// All-time course income after discounts / everything charged, per currency.
  final Map<String, double> incomeByCurrency, collectedByCurrency;

  // ── D-062 blocks ─────────────────────────────────────────────────────────
  /// null = the server has no `organizations` block.
  final int? orgTotal;
  final int orgActive, orgPendingApproval;
  final Map<String, int> orgByType;
  final List<AdminDayPoint> series;
  final bool hasAlerts;
  final List<AdminAlert> alerts;
  final bool hasRealtime;

  /// Live events in the last 24 h; null = unknown (no Redis, or an older server).
  final int? eventsLast24h;

  int get users => students + teachers;
  bool get hasOrganizations => orgTotal != null;
  bool get hasSeries => series.isNotEmpty;

  /// The home has nothing to show at all (a fresh platform).
  bool get isEmpty => users == 0 && courses == 0 && (orgTotal ?? 0) == 0 && !hasSeries;

  // ── series views ─────────────────────────────────────────────────────────
  List<double> get signupsSpark => [for (final p in series) p.signups.toDouble()];
  List<double> get enrollmentsSpark => [for (final p in series) p.enrollments.toDouble()];
  List<double> get revenueSpark => [for (final p in series) p.revenueTotal];

  int get signups30 => series.fold(0, (s, p) => s + p.signups);
  int get enrollments30 => series.fold(0, (s, p) => s + p.enrollments);
  int get liveSessions30 => series.fold(0, (s, p) => s + p.liveSessions);
  int get complaints30 => series.fold(0, (s, p) => s + p.complaints);

  /// Gross revenue of the window, per currency (the donut; empty without a series or without a sale).
  Map<String, double> get revenue30ByCurrency {
    final out = <String, double>{};
    for (final p in series) {
      p.revenue.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    out.removeWhere((_, v) => v <= 0);
    return out;
  }

  /// The currency that earned most in the window (the figure of the revenue tile), or null.
  String? get mainCurrency {
    final m = revenue30ByCurrency;
    if (m.isEmpty) return null;
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  double? get signupsDelta => halfDelta(signupsSpark);
  double? get enrollmentsDelta => halfDelta(enrollmentsSpark);
  double? get revenueDelta => halfDelta(revenueSpark);

  /// The last [n] days (for the bar chart: 30 groups do not fit a phone).
  List<AdminDayPoint> recent(int n) => series.length <= n ? series : series.sublist(series.length - n);

  /// Something happened in the window (else the charts show their empty state).
  bool get hasActivity => series.any((p) => p.signups > 0 || p.enrollments > 0 || p.revenueTotal > 0);

  // ── alerts ───────────────────────────────────────────────────────────────
  AdminAlert? alert(String key) {
    for (final a in alerts) {
      if (a.key == key) return a;
    }
    return null;
  }

  /// Failed background jobs in 24 h (0 when the server reports none).
  int get jobsFailed24h => alert('jobs_failed_24h')?.count ?? 0;
  Map<String, int> get jobsFailedByKind => alert('jobs_failed_24h')?.byKind ?? const {};

  /// What the "Needs you" grid draws beside the alerts: a count the alerts already carry is drawn ONCE.
  bool get transfersInAlerts => alert('transfers_pending') != null;
  bool get orgApprovalsInAlerts => alert('orgs_pending_approval') != null;

  /// Everything that waits for a decision (the section count). [pendingPayouts] is the shell's live number.
  int queueTotal(int pendingPayouts) {
    var n = pendingPayouts + pendingSubscriptions;
    for (final a in alerts) {
      n += a.key == 'otp_provider_unconfigured' ? 0 : a.count;
    }
    if (!transfersInAlerts) n += pendingTransfers;
    if (!orgApprovalsInAlerts) n += orgPendingApproval;
    return n;
  }
}
