// lib/features/org/workspace/ws_models.dart
//
// The teacher workspace's plain values and pure logic (D-1150 – D-1158, docs/teacher-org/PLAN.md): the units I
// manage / belong to, a unit's people, a person's history, alerts, pins, list filters. No Flutter widgets, no
// calls — unit-tested in test/org/ws_models_test.dart.
library;

import 'package:flutter_education_app/config/app_config.dart';

import '../home/org_home_logic.dart' show OrgTask;

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) _map(e)] : const [];
int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String _str(Object? v) => v == null ? '' : '$v';
DateTime? _date(Object? v) {
  final s = _str(v);
  if (s.isEmpty) return null;
  // the server stores naive UTC
  return DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z')?.toLocal();
}

String _pick(String ar, String en) {
  final ar1 = ar.trim(), en1 = en.trim();
  if (AppConfig.lang == 'ar') return ar1.isNotEmpty ? ar1 : en1;
  return en1.isNotEmpty ? en1 : ar1;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Units (GET …/my-workspace)
// ═════════════════════════════════════════════════════════════════════════════

enum WsUnitRole { head, manager, member }

WsUnitRole _role(String s) => switch (s) { 'head' => WsUnitRole.head, 'manager' => WsUnitRole.manager, _ => WsUnitRole.member };

class WsUnit {
  const WsUnit({
    required this.id,
    this.unitType = 'dept',
    this.nameAr = '',
    this.nameEn = '',
    this.icon,
    this.color,
    this.logoUrl,
    this.people = 0,
    this.team = 0,
    this.waiting = 0,
    this.role = WsUnitRole.member,
  });

  factory WsUnit.fromJson(Map<String, dynamic> j) => WsUnit(
        id: _int(j['id']),
        unitType: _str(j['unit_type']).isEmpty ? 'dept' : _str(j['unit_type']),
        nameAr: _str(j['name_ar']),
        nameEn: _str(j['name_en']),
        icon: j['icon'] == null ? null : _str(j['icon']),
        color: j['color'] == null ? null : _str(j['color']),
        logoUrl: j['logo_url'] == null ? null : _str(j['logo_url']),
        people: _int(j['people']),
        team: _int(j['team']),
        waiting: _int(j['waiting']),
        role: _role(_str(j['role'])),
      );

  final int id;
  final String unitType;
  final String nameAr, nameEn;
  final String? icon, color, logoUrl;
  final int people, team, waiting;
  final WsUnitRole role;

  String get name => _pick(nameAr, nameEn);
  bool get manages => role != WsUnitRole.member;
}

class WsStats {
  const WsStats({
    this.peopleManaged = 0,
    this.teamManaged = 0,
    this.membersTotal = 0,
    this.alertsActive = 0,
    this.alertsHigh = 0,
    this.alertsUnread = 0,
    this.requestsOpen = 0,
    this.requestsOverdue = 0,
    this.votesWaiting = 0,
    this.nextSession,
  });

  factory WsStats.fromJson(Map<String, dynamic> j) => WsStats(
        peopleManaged: _int(j['people_managed']),
        teamManaged: _int(j['team_managed']),
        membersTotal: _int(j['members_total']),
        alertsActive: _int(j['alerts_active']),
        alertsHigh: _int(j['alerts_high']),
        alertsUnread: _int(j['alerts_unread']),
        requestsOpen: _int(j['requests_open']),
        requestsOverdue: _int(j['requests_overdue']),
        votesWaiting: _int(j['votes_waiting']),
        nextSession: j['next_session'] is Map ? _map(j['next_session']) : null,
      );

  final int peopleManaged, teamManaged, membersTotal, alertsActive, alertsHigh, alertsUnread, requestsOpen, requestsOverdue, votesWaiting;

  /// The server's next-session row as it sends it (title / starts_at …), or null.
  final Map<String, dynamic>? nextSession;
}

class WsHome {
  const WsHome({this.managed = const [], this.memberOf = const [], this.stats = const WsStats(), this.weeks = const {}});

  factory WsHome.fromJson(Map<String, dynamic> j) {
    final w = _map(j['weeks']);
    return WsHome(
      managed: [for (final u in _maps(j['managed'])) WsUnit.fromJson(u)],
      memberOf: [for (final u in _maps(j['member_of'])) WsUnit.fromJson(u)],
      stats: WsStats.fromJson(_map(j['stats'])),
      weeks: {for (final e in w.entries) e.key: [for (final n in (e.value is List ? e.value as List : const [])) _int(n)]},
    );
  }

  final List<WsUnit> managed, memberOf;
  final WsStats stats;

  /// Weekly series, oldest first (`people`, `requests`, …).
  final Map<String, List<int>> weeks;

  List<WsUnit> get all => [...managed, ...memberOf];
  WsUnit? unit(int id) => all.where((u) => u.id == id).firstOrNull;
}

// ═════════════════════════════════════════════════════════════════════════════
//  People + history
// ═════════════════════════════════════════════════════════════════════════════

enum WsPersonKind { head, team, member }

WsPersonKind wsKindOf(String s) => switch (s) { 'head' => WsPersonKind.head, 'team' => WsPersonKind.team, _ => WsPersonKind.member };

String wsKindKey(WsPersonKind k) => switch (k) { WsPersonKind.head => 'head', WsPersonKind.team => 'team', WsPersonKind.member => 'member' };

class WsPerson {
  const WsPerson({
    required this.userId,
    this.name = '',
    this.avatarUrl,
    this.username,
    this.kind = WsPersonKind.member,
    this.title,
    this.joinedAt,
    this.joinedVia,
    this.email,
    this.phone,
    this.raw = const {},
  });

  factory WsPerson.fromJson(Map<String, dynamic> j) => WsPerson(
        userId: _int(j['user_id'] ?? j['id']),
        name: _str(j['name']),
        avatarUrl: _str(j['avatar_url']).isEmpty ? null : _str(j['avatar_url']),
        username: _str(j['username']).isEmpty ? null : _str(j['username']),
        kind: wsKindOf(_str(j['kind'])),
        title: _str(j['title']).isEmpty ? null : _str(j['title']),
        joinedAt: _date(j['joined_at']),
        joinedVia: _str(j['joined_via']).isEmpty ? null : _str(j['joined_via']),
        email: _str(j['email']).isEmpty ? null : _str(j['email']),
        phone: _str(j['phone']).isEmpty ? null : _str(j['phone']),
        raw: j,
      );

  final int userId;
  final String name;
  final String? avatarUrl, username, title, joinedVia, email, phone;
  final WsPersonKind kind;
  final DateTime? joinedAt;

  /// The row as the server sent it: the removal snapshot sent back by Undo (`op: restore`).
  final Map<String, dynamic> raw;
}

class WsCan {
  const WsCan({this.manage = false, this.bulk = false});
  factory WsCan.fromJson(Map<String, dynamic> j) => WsCan(manage: j['manage'] == true, bulk: j['bulk'] == true);
  final bool manage, bulk;
}

class WsPeoplePage {
  const WsPeoplePage({this.items = const [], this.total = 0, this.page = 1, this.pages = 1, this.can = const WsCan()});

  factory WsPeoplePage.fromJson(Map<String, dynamic> j) => WsPeoplePage(
        items: [for (final p in _maps(j['items'])) WsPerson.fromJson(p)],
        total: _int(j['total']),
        page: _int(j['page']) == 0 ? 1 : _int(j['page']),
        pages: _int(j['pages']) == 0 ? 1 : _int(j['pages']),
        can: WsCan.fromJson(_map(j['can'])),
      );

  final List<WsPerson> items;
  final int total, page, pages;
  final WsCan can;
  bool get hasMore => page < pages;
}

class WsHistoryRow {
  const WsHistoryRow({required this.id, this.action = '', this.summary = '', this.actorId, this.actorName = '', this.actorAvatar, this.at});

  factory WsHistoryRow.fromJson(Map<String, dynamic> j) {
    final a = _map(j['actor']);
    return WsHistoryRow(
      id: _int(j['id']),
      action: _str(j['action']),
      summary: _str(j['summary']),
      actorId: _intOrNull(a['id']),
      actorName: _str(a['name']),
      actorAvatar: _str(a['avatar_url']).isEmpty ? null : _str(a['avatar_url']),
      at: _date(j['created_at']),
    );
  }

  final int id;
  final String action, summary, actorName;
  final int? actorId;
  final String? actorAvatar;
  final DateTime? at;
}

class WsPersonDetail {
  const WsPersonDetail({required this.person, this.historyAll = false, this.history = const [], this.nextCursor});

  factory WsPersonDetail.fromJson(Map<String, dynamic> j) {
    final h = _map(j['history']);
    final next = h['next_cursor'];
    return WsPersonDetail(
      person: WsPerson.fromJson(_map(j['person'])),
      historyAll: _str(j['history_scope']) == 'all',
      history: [for (final r in _maps(h['items'])) WsHistoryRow.fromJson(r)],
      nextCursor: next == null || '$next'.isEmpty ? null : '$next',
    );
  }

  final WsPerson person;

  /// true = everyone's history (I manage the unit); false = only my own actions (D-1152).
  final bool historyAll;
  final List<WsHistoryRow> history;
  final String? nextCursor;
}

/// Groups history rows by local day, newest first (the details timeline).
List<(DateTime, List<WsHistoryRow>)> wsHistoryByDay(List<WsHistoryRow> rows) {
  final out = <(DateTime, List<WsHistoryRow>)>[];
  final sorted = [...rows]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  for (final r in sorted) {
    final d = r.at ?? DateTime(0);
    final day = DateTime(d.year, d.month, d.day);
    if (out.isNotEmpty && out.last.$1 == day) {
      out.last.$2.add(r);
    } else {
      out.add((day, [r]));
    }
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
//  People filters (removable chips, saved filters)
// ═════════════════════════════════════════════════════════════════════════════

enum WsSort { name, newest, oldest }

class WsPeopleFilter {
  const WsPeopleFilter({this.q = '', this.kinds = const {}, this.joinedFrom, this.joinedTo, this.sort = WsSort.name});

  factory WsPeopleFilter.fromJson(Map<String, dynamic> j) => WsPeopleFilter(
        q: _str(j['q']),
        kinds: {for (final k in (j['kinds'] is List ? j['kinds'] as List : const [])) wsKindOf('$k')},
        joinedFrom: DateTime.tryParse(_str(j['from'])),
        joinedTo: DateTime.tryParse(_str(j['to'])),
        sort: WsSort.values.where((s) => s.name == _str(j['sort'])).firstOrNull ?? WsSort.name,
      );

  final String q;
  final Set<WsPersonKind> kinds;
  final DateTime? joinedFrom, joinedTo;
  final WsSort sort;

  bool get isEmpty => q.trim().isEmpty && kinds.isEmpty && joinedFrom == null && joinedTo == null;

  /// How many removable chips the filter draws (search excluded: it has its own field).
  int get chipCount => kinds.length + (joinedFrom != null || joinedTo != null ? 1 : 0);

  WsPeopleFilter copyWith({String? q, Set<WsPersonKind>? kinds, DateTime? joinedFrom, DateTime? joinedTo, WsSort? sort, bool clearDates = false}) =>
      WsPeopleFilter(
        q: q ?? this.q,
        kinds: kinds ?? this.kinds,
        joinedFrom: clearDates ? null : (joinedFrom ?? this.joinedFrom),
        joinedTo: clearDates ? null : (joinedTo ?? this.joinedTo),
        sort: sort ?? this.sort,
      );

  /// One chip removed: [kind] drops that kind, null drops the date range.
  WsPeopleFilter without({WsPersonKind? kind}) =>
      kind != null ? copyWith(kinds: {...kinds}..remove(kind)) : copyWith(clearDates: true);

  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Query parameters for GET …/people (the server takes ONE kind; several kinds are sent comma-separated).
  Map<String, String> query({int page = 1, int size = 30}) => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (kinds.isNotEmpty) 'kind': (kinds.map(wsKindKey).toList()..sort()).join(','),
        if (joinedFrom != null) 'joined_from': _d(joinedFrom!),
        if (joinedTo != null) 'joined_to': _d(joinedTo!),
        'sort': switch (sort) { WsSort.name => 'name', WsSort.newest => '-joined', WsSort.oldest => 'joined' },
        'page': '$page',
        'size': '$size',
      };

  Map<String, dynamic> toJson() => {
        if (q.isNotEmpty) 'q': q,
        if (kinds.isNotEmpty) 'kinds': (kinds.map(wsKindKey).toList()..sort()),
        if (joinedFrom != null) 'from': _d(joinedFrom!),
        if (joinedTo != null) 'to': _d(joinedTo!),
        'sort': sort.name,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Alerts (GET …/my-alerts)
// ═════════════════════════════════════════════════════════════════════════════

enum WsSeverity { high, medium, low }

WsSeverity _sev(String s) => switch (s) { 'high' => WsSeverity.high, 'low' => WsSeverity.low, _ => WsSeverity.medium };

class WsAlertSource {
  const WsAlertSource({this.type = 'organization', this.id, this.nameAr = '', this.nameEn = ''});
  factory WsAlertSource.fromJson(Map<String, dynamic> j) =>
      WsAlertSource(type: _str(j['type']).isEmpty ? 'organization' : _str(j['type']), id: _intOrNull(j['id']), nameAr: _str(j['name_ar']), nameEn: _str(j['name_en']));

  final String type;
  final int? id;
  final String nameAr, nameEn;

  /// The organization's own alerts (no department; the server says `organization`).
  bool get isOrg => type == 'organization' || type == 'org';

  /// The group key: one group per department, one for the organization itself.
  String get key => '$type:${id ?? 0}';
  String get name => _pick(nameAr, nameEn);
}

class WsAlert {
  const WsAlert({
    required this.key,
    this.kind = '',
    this.source = const WsAlertSource(),
    this.severity = WsSeverity.medium,
    this.titleAr = '',
    this.titleEn = '',
    this.subtitleAr = '',
    this.subtitleEn = '',
    this.personId,
    this.personName,
    this.personAvatar,
    this.deptId,
    this.at,
    this.link = const {},
    this.read = false,
    this.snoozedUntil,
    this.raw = const {},
  });

  factory WsAlert.fromJson(Map<String, dynamic> j) {
    final p = _map(j['person']);
    return WsAlert(
      key: _str(j['key']),
      kind: _str(j['kind']),
      source: WsAlertSource.fromJson(_map(j['source'])),
      severity: _sev(_str(j['severity'])),
      titleAr: _str(j['title_ar']),
      titleEn: _str(j['title_en']),
      subtitleAr: _str(j['subtitle_ar']),
      subtitleEn: _str(j['subtitle_en']),
      personId: _intOrNull(p['id']),
      personName: _str(p['name']).isEmpty ? null : _str(p['name']),
      personAvatar: _str(p['avatar_url']).isEmpty ? null : _str(p['avatar_url']),
      deptId: _intOrNull(j['dept_id']),
      at: _date(j['created_at']),
      link: _map(j['link']),
      read: j['read'] == true,
      snoozedUntil: _date(j['snoozed_until']),
      raw: j,
    );
  }

  final String key, kind;
  final WsAlertSource source;
  final WsSeverity severity;
  final String titleAr, titleEn, subtitleAr, subtitleEn;
  final int? personId, deptId;
  final String? personName, personAvatar;
  final DateTime? at;

  /// The server's deep link ({section, sub, dept_id, kind, id}) for alerts that are not about a person.
  final Map<String, dynamic> link;
  final bool read;
  final DateTime? snoozedUntil;

  /// The row as the server sent it ([task] reads its `actions` / `version`).
  final Map<String, dynamic> raw;

  /// The organization task behind this alert, with its one-tap decisions (the home's OrgTask); null for an
  /// attention row or a task without actions this app can name.
  OrgTask? get task {
    if ((raw['actions'] is! List) || (raw['actions'] as List).isEmpty) return null;
    final t = OrgTask.fromJson({...raw, 'id': key, 'urgency': raw['severity']});
    return t != null && t.oneTap ? t : null;
  }

  String get title => _pick(titleAr, titleEn);
  String get subtitle => _pick(subtitleAr, subtitleEn);

  /// Tapping opens the person's profile in that unit when the alert is about someone there (D-1156).
  bool get opensPerson => personId != null && deptId != null;

  WsAlert copyWith({bool? read}) => WsAlert(
        key: key, kind: kind, source: source, severity: severity, titleAr: titleAr, titleEn: titleEn,
        subtitleAr: subtitleAr, subtitleEn: subtitleEn, personId: personId, personName: personName,
        personAvatar: personAvatar, deptId: deptId, at: at, link: link, read: read ?? this.read, snoozedUntil: snoozedUntil,
        raw: raw,
      );
}

class WsAlertCounts {
  const WsAlertCounts({this.active = 0, this.unread = 0, this.high = 0});
  factory WsAlertCounts.fromJson(Map<String, dynamic> j) => WsAlertCounts(active: _int(j['active']), unread: _int(j['unread']), high: _int(j['high']));
  final int active, unread, high;
}

/// A source's alerts: the group card's header and rows.
class WsAlertGroup {
  const WsAlertGroup(this.source, this.alerts);
  final WsAlertSource source;
  final List<WsAlert> alerts;
  int get unread => alerts.where((a) => !a.read).length;
  WsSeverity get worst => alerts.map((a) => a.severity).fold(WsSeverity.low, (w, s) => s.index < w.index ? s : w);
}

/// One group per source. Groups: the worst severity first, then the most unread, then the newest alert; rows inside:
/// unread first, then severity, then newest. The organization's own group (no department) goes last on a tie.
List<WsAlertGroup> wsGroupAlerts(List<WsAlert> alerts) {
  final by = <String, List<WsAlert>>{};
  final src = <String, WsAlertSource>{};
  for (final a in alerts) {
    (by[a.source.key] ??= []).add(a);
    src[a.source.key] ??= a.source;
  }
  DateTime newest(List<WsAlert> l) => l.map((a) => a.at ?? DateTime(0)).fold(DateTime(0), (m, d) => d.isAfter(m) ? d : m);
  final groups = [
    for (final e in by.entries)
      WsAlertGroup(
        src[e.key]!,
        [...e.value]..sort((a, b) {
            if (a.read != b.read) return a.read ? 1 : -1;
            final s = a.severity.index.compareTo(b.severity.index);
            if (s != 0) return s;
            return (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0));
          }),
      ),
  ];
  groups.sort((a, b) {
    final w = a.worst.index.compareTo(b.worst.index);
    if (w != 0) return w;
    final u = b.unread.compareTo(a.unread);
    if (u != 0) return u;
    final n = newest(b.alerts).compareTo(newest(a.alerts));
    if (n != 0) return n;
    return (a.source.isOrg ? 1 : 0).compareTo(b.source.isOrg ? 1 : 0);
  });
  return groups;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pins + display preferences (stored per user + organization, ws_prefs.dart)
// ═════════════════════════════════════════════════════════════════════════════

/// What a pin points at: a whole tab (`tab:management`), one unit (`unit:12`), one Overview box (`box:alerts`) or
/// one organization page of an admin's Management tab (`section:members`, the OrgTabs sub key, D-1160).
class WsPin {
  const WsPin(this.kind, this.ref, {this.labelAr = '', this.labelEn = ''});

  static WsPin? parse(Object? v) {
    final m = _map(v);
    final kind = _str(m['kind']), ref = _str(m['ref']);
    if (!const {'tab', 'unit', 'box', 'section'}.contains(kind) || ref.isEmpty) return null;
    return WsPin(kind, ref, labelAr: _str(m['ar']), labelEn: _str(m['en']));
  }

  final String kind, ref;

  /// The label when it was pinned (a unit's name), shown while the unit list loads.
  final String labelAr, labelEn;

  String get id => '$kind:$ref';
  String get label => _pick(labelAr, labelEn);
  int? get unitId => kind == 'unit' ? int.tryParse(ref) : null;

  Map<String, dynamic> toJson() => {'kind': kind, 'ref': ref, if (labelAr.isNotEmpty) 'ar': labelAr, if (labelEn.isNotEmpty) 'en': labelEn};

  @override
  bool operator ==(Object other) => other is WsPin && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// From this many pins the Pinned tab's strip gets its "All pinned" grid (D-1151).
const wsPinStripMax = 10;

/// Drops pins whose unit I no longer belong to (keeps tabs and boxes); keeps the order.
List<WsPin> wsLivePins(List<WsPin> pins, Set<int> unitIds) =>
    [for (final p in pins) if (p.unitId == null || unitIds.contains(p.unitId)) p];

enum WsDisplay { boxes, tabs }

enum WsAlertView { grouped, expanded, list }

/// Per user + organization display preferences (D-1157). [scope] keys: 'management', 'membership'.
class WsPrefs {
  const WsPrefs({
    this.display = const {},
    this.mainUnit = const {},
    this.mainSection = const {},
    this.focus = false,
    this.pins = const [],
    this.savedFilters = const {},
    this.alertView = WsAlertView.grouped,
  });

  factory WsPrefs.fromJson(Map<String, dynamic> j) => WsPrefs(
        display: {
          for (final e in _map(j['display']).entries)
            e.key: WsDisplay.values.where((d) => d.name == '${e.value}').firstOrNull ?? WsDisplay.boxes,
        },
        mainUnit: {for (final e in _map(j['main']).entries) if (_intOrNull(e.value) != null) e.key: _intOrNull(e.value)!},
        mainSection: {for (final e in _map(j['main_section']).entries) if (_str(e.value).isNotEmpty) e.key: _str(e.value)},
        focus: j['focus'] == true,
        pins: [for (final p in (j['pins'] is List ? j['pins'] as List : const [])) ?WsPin.parse(p)],
        savedFilters: {for (final e in _map(j['filters']).entries) e.key: WsPeopleFilter.fromJson(_map(e.value))},
        alertView: WsAlertView.values.where((v) => v.name == _str(j['alert_view'])).firstOrNull ?? WsAlertView.grouped,
      );

  final Map<String, WsDisplay> display;
  final Map<String, int> mainUnit;

  /// An admin's main tab when it is an organization page (D-1160): scope → OrgTabs sub key. Set together with
  /// [mainUnit] cleared for that scope (one main per scope).
  final Map<String, String> mainSection;
  final bool focus;
  final List<WsPin> pins;
  final Map<String, WsPeopleFilter> savedFilters;
  final WsAlertView alertView;

  WsDisplay displayOf(String scope) => display[scope] ?? WsDisplay.boxes;
  bool pinned(WsPin p) => pins.contains(p);

  /// One main per scope: a unit (clears the section) or an organization page (clears the unit).
  WsPrefs setMainUnit(String scope, int id) =>
      copyWith(mainUnit: {...mainUnit, scope: id}, mainSection: {...mainSection}..remove(scope));
  WsPrefs setMainSection(String scope, String key) =>
      copyWith(mainSection: {...mainSection, scope: key}, mainUnit: {...mainUnit}..remove(scope));

  /// The unit a tabs view opens on: the pinned main one when it is still in [units], else the first.
  int? openUnit(String scope, List<int> units) {
    final m = mainUnit[scope];
    if (m != null && units.contains(m)) return m;
    return units.firstOrNull;
  }

  WsPrefs copyWith({
    Map<String, WsDisplay>? display,
    Map<String, int>? mainUnit,
    Map<String, String>? mainSection,
    bool? focus,
    List<WsPin>? pins,
    Map<String, WsPeopleFilter>? savedFilters,
    WsAlertView? alertView,
  }) =>
      WsPrefs(
        display: display ?? this.display,
        mainUnit: mainUnit ?? this.mainUnit,
        mainSection: mainSection ?? this.mainSection,
        focus: focus ?? this.focus,
        pins: pins ?? this.pins,
        savedFilters: savedFilters ?? this.savedFilters,
        alertView: alertView ?? this.alertView,
      );

  /// Pin or unpin [p] (a new pin goes last).
  WsPrefs togglePin(WsPin p) => copyWith(pins: pinned(p) ? [for (final x in pins) if (x != p) x] : [...pins, p]);

  /// Moves the pin at [from] to [to] (ReorderableListView indices: [to] counts the moved item).
  WsPrefs movePin(int from, int to) {
    final l = [...pins];
    if (from < 0 || from >= l.length) return this;
    final x = l.removeAt(from);
    l.insert((to > from ? to - 1 : to).clamp(0, l.length), x);
    return copyWith(pins: l);
  }

  Map<String, dynamic> toJson() => {
        'display': {for (final e in display.entries) e.key: e.value.name},
        'main': mainUnit,
        'main_section': mainSection,
        'focus': focus,
        'pins': [for (final p in pins) p.toJson()],
        'filters': {for (final e in savedFilters.entries) e.key: e.value.toJson()},
        'alert_view': alertView.name,
      };
}
