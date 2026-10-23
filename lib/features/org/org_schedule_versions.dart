// lib/features/org/org_schedule_versions.dart — pure logic shared by alternatives, comparison and timetable copies.
//
//   RelaxationPolicy      the order soft restrictions may be relaxed in (students first … teachers last)
//   VersionMetrics        measured facts about one timetable version (conflicts, unplaced, relaxations, rooms, load)
//   VersionDiff           what changed between two versions (days, periods, times, rooms, staff, groups)
//   rankVersions          feasible first, then the least relaxation of the most protected tier, then stability
//   memberTimetable       one teacher's / assistant's / group's / room's sessions only
//   TimetableCopy         a stored revision used as a copy; outdated once the live timetable differs from it
//
// Nothing here talks to the server or guesses: a figure the server did not send stays null and is shown as "—".
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:intl/intl.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart' show orgDays;
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Relaxation priority
// ═════════════════════════════════════════════════════════════════════════════

/// Relaxable restriction tiers, in the default order they may be relaxed (first = relaxed first).
/// Hard rules (eligibility, capacity, facilities, double booking, unavailability) are not tiers: they never relax.
const relaxTiers = ['student_prefs', 'add_capacity', 'rooms', 'assistant_prefs', 'other_soft', 'teacher_prefs'];

String relaxTierLabel(String tier) => switch (tier) {
      'student_prefs' => t('تفضيلات الطلاب', 'Student preferences'),
      'add_capacity' => t('إضافة أيام أو فترات', 'Add days or periods'),
      'rooms' => t('أماكن أو ترتيب تدريس بديل', 'Alternative rooms / arrangements'),
      'assistant_prefs' => t('تفضيلات المعيدين', 'Assistant preferences'),
      'other_soft' => t('قيود مرنة أخرى', 'Other soft constraints'),
      'teacher_prefs' => t('تفضيلات المدرسين', 'Teacher preferences'),
      _ => tier,
    };

class RelaxationPolicy {
  const RelaxationPolicy(this.order);

  /// First = relaxed first. Teacher preferences stay last unless an administrator moves them.
  final List<String> order;

  static const standard = RelaxationPolicy(relaxTiers);

  /// settings.relaxation_priority; unknown or missing tiers fall back to the default order.
  factory RelaxationPolicy.fromSettings(Map<String, dynamic> settings) {
    final raw = [for (final x in (settings['relaxation_priority'] as List?) ?? const []) '$x'].where(relaxTiers.contains).toSet().toList();
    return RelaxationPolicy([...raw, ...relaxTiers.where((x) => !raw.contains(x))]);
  }

  List<String> toJson() => List.of(order);

  /// 0 = relaxed first (cheapest); higher = more protected.
  int rank(String tier) => order.indexOf(tier).clamp(0, order.length);

  /// Tiers from the most protected to the least — the order versions are compared in.
  List<String> get protectedFirst => order.reversed.toList();

  RelaxationPolicy move(String tier, int by) {
    final o = List.of(order);
    final i = o.indexOf(tier), j = (i + by).clamp(0, o.length - 1);
    if (i < 0 || i == j) return this;
    o.insert(j, o.removeAt(i));
    return RelaxationPolicy(o);
  }
}

/// The tier a solver `relaxed` entry belongs to, from the member's role.
String relaxedTier(Map<String, dynamic> r, Map<int, String> roleOf) => switch (r['tier'] ?? roleOf[asInt(r['user_id'])]) {
      'teacher' || 'teacher_prefs' => 'teacher_prefs',
      'teacher_assistant' || 'assistant_prefs' => 'assistant_prefs',
      'student' || 'student_prefs' => 'student_prefs',
      _ => 'other_soft',
    };

/// The solver's soft weights for the personal preferences (SOFT_WEIGHTS in org_schedule_solver.py).
const relaxWeightAvoid = 40.0, relaxWeightNotPreferred = 12.0;

double relaxedSeverity(Map<String, dynamic> r) =>
    asInt(r['avoided_cell_used'] ?? 0) * relaxWeightAvoid + asInt(r['outside_preferred'] ?? 0) * relaxWeightNotPreferred;

// ═════════════════════════════════════════════════════════════════════════════
//  Metrics, diff and ranking
// ═════════════════════════════════════════════════════════════════════════════

class VersionMetrics {
  const VersionMetrics({
    required this.sessions,
    this.hardConflicts,
    this.required,
    this.unplacedLectures = 0,
    this.unplacedLabs = 0,
    this.relaxBy = const {},
    this.softCost,
    this.roomUse,
    this.load = const {},
    this.days = const [],
    this.periodIds = const [],
  });

  final int sessions; // slots in the version
  final int? hardConflicts; // null = not validated (a stored revision has no validate report)
  final int? required; // sessions_required from the generation report
  final int unplacedLectures, unplacedLabs;
  final Map<String, double> relaxBy; // tier → severity
  final double? softCost;
  final double? roomUse; // used room-cells / (rooms × days × periods); null = no rooms or no cells
  final Map<int, int> load; // staff user id → periods taught
  final List<String> days;
  final List<int> periodIds;

  int get unplaced => unplacedLectures + unplacedLabs;
  double get relaxTotal => relaxBy.values.fold(0.0, (a, b) => a + b);

  /// True only when the server checked it and nothing is left: unknown is never reported as feasible.
  bool get feasible => hardConflicts == 0 && unplaced == 0;

  int get maxLoad => load.values.fold(0, (a, b) => b > a ? b : a);

  factory VersionMetrics.of({
    required List<Map<String, dynamic>> slots,
    Map<String, dynamic> summary = const {},
    List<Map<String, dynamic>>? conflicts,
    Map<int, String> roleOf = const {},
    int roomCount = 0,
    List<String> days = const [],
    List<int> periodIds = const [],
  }) {
    final stats = asMap(summary['stats']);
    var lec = 0, lab = 0;
    for (final u in asMapList(summary['unscheduled'])) {
      final n = asInt(u['missing'] ?? 1);
      if (u['kind'] == 'lab') {
        lab += n;
      } else {
        lec += n;
      }
    }
    final relax = <String, double>{};
    for (final r in asMapList(summary['relaxed'])) {
      relax.update(relaxedTier(r, roleOf), (v) => v + relaxedSeverity(r), ifAbsent: () => relaxedSeverity(r));
    }
    final load = <int, int>{};
    final roomCells = <String>{};
    for (final s in slots) {
      final span = asInt(s['periods'] ?? s['span'] ?? 1, 1);
      for (final k in ['teacher_id', 'assistant_id', 'admin_assistant_id']) {
        if (s[k] != null) load.update(asInt(s[k]), (v) => v + span, ifAbsent: () => span);
      }
      if (s['room_id'] != null) roomCells.add('${s['room_id']}|${s['day']}|${s['period_id']}');
    }
    final cells = roomCount * days.length * periodIds.length;
    return VersionMetrics(
      sessions: slots.length,
      hardConflicts: conflicts?.where((c) => c['severity'] == 'error').length,
      required: stats['sessions_required'] == null ? null : asInt(stats['sessions_required']),
      unplacedLectures: lec,
      unplacedLabs: lab,
      relaxBy: relax,
      softCost: (stats['soft_cost'] as num?)?.toDouble(),
      roomUse: cells == 0 ? null : roomCells.length / cells,
      load: load,
      days: days.isNotEmpty ? days : orgDays.where((d) => slots.any((s) => s['day'] == d)).toList(),
      periodIds: periodIds.isNotEmpty ? periodIds : ({for (final s in slots) asInt(s['period_id'])}.toList()..sort()),
    );
  }
}

/// Lower is better. Order: server-confirmed feasible → fewer hard conflicts (unknown counts as worse than 0) → fewer
/// unplaced sessions → less relaxation of the MOST protected tier, then the next … → lower soft cost → fewer changes.
/// So a version is never ranked better for having fewer conflicts if it relaxes a more protected restriction.
int compareVersions(VersionMetrics a, VersionMetrics b, RelaxationPolicy policy, {int changesA = 0, int changesB = 0}) {
  int cmp(num x, num y) => x.compareTo(y);
  final checks = <int>[
    cmp(a.feasible ? 0 : 1, b.feasible ? 0 : 1),
    cmp(a.hardConflicts ?? 1 << 20, b.hardConflicts ?? 1 << 20),
    cmp(a.unplaced, b.unplaced),
    for (final tier in policy.protectedFirst) cmp(a.relaxBy[tier] ?? 0, b.relaxBy[tier] ?? 0),
    cmp(a.softCost ?? 0, b.softCost ?? 0),
    cmp(changesA, changesB),
  ];
  return checks.firstWhere((c) => c != 0, orElse: () => 0);
}

/// Indexes of [all] best first (stable for ties).
List<int> rankVersions(List<VersionMetrics> all, RelaxationPolicy policy, {List<int>? changes}) {
  final idx = List<int>.generate(all.length, (i) => i);
  idx.sort((a, b) {
    final c = compareVersions(all[a], all[b], policy, changesA: changes?[a] ?? 0, changesB: changes?[b] ?? 0);
    return c != 0 ? c : a.compareTo(b);
  });
  return idx;
}

String rankingExplanation(RelaxationPolicy policy) => t(
    'الترتيب: الصالح بالكامل (تحقق منه الخادم) أولاً، ثم الأقل تعارضات أساسية، ثم الأقل حصصاً بلا مكان، ثم الأقل تخفيفاً للأكثر حماية: ${policy.protectedFirst.map(relaxTierLabel).join(' ← ')}، ثم التكلفة المرنة، ثم الأقل تغييراً.',
    'Ranking: fully valid (checked by the server) first, then fewest hard conflicts, then fewest unplaced sessions, then the least relaxation of the most protected tier: ${policy.protectedFirst.map(relaxTierLabel).join(' → ')}, then soft cost, then fewest changes.');

/// A session's identity across versions: the same course · kind · group, n-th occurrence.
List<String> _keys(List<Map<String, dynamic>> slots) {
  final seen = <String, int>{};
  final sorted = [...slots]..sort((a, b) => '${a['day']}|${a['period_id']}'.compareTo('${b['day']}|${b['period_id']}'));
  return [
    for (final s in sorted)
      () {
        final base = '${s['course_id']}|${s['kind'] ?? 'lecture'}|${s['group_no'] ?? 1}';
        final n = seen.update(base, (v) => v + 1, ifAbsent: () => 0);
        return '$base#$n';
      }()
  ];
}

Map<String, Map<String, dynamic>> _byKey(List<Map<String, dynamic>> slots) {
  final sorted = [...slots]..sort((a, b) => '${a['day']}|${a['period_id']}'.compareTo('${b['day']}|${b['period_id']}'));
  final keys = _keys(slots);
  return {for (var i = 0; i < sorted.length; i++) keys[i]: sorted[i]};
}

class VersionDiff {
  const VersionDiff({
    this.added = const [],
    this.removed = const [],
    this.timeChanged = const [],
    this.roomChanged = const [],
    this.staffChanged = const [],
    this.daysAdded = const [],
    this.daysRemoved = const [],
    this.periodsAdded = const [],
    this.periodsRemoved = const [],
    this.groupsChanged = const {},
  });

  final List<Map<String, dynamic>> added, removed; // sessions only in b / only in a
  final List<(Map<String, dynamic>, Map<String, dynamic>)> timeChanged, roomChanged, staffChanged; // (a, b)
  final List<String> daysAdded, daysRemoved;
  final List<int> periodsAdded, periodsRemoved;
  final Map<String, (int, int)> groupsChanged; // 'course|kind' → (groups in a, groups in b)

  int get total => added.length + removed.length + {...timeChanged.map((x) => x.$2['id']), ...roomChanged.map((x) => x.$2['id']), ...staffChanged.map((x) => x.$2['id'])}.length;
  bool get isEmpty => total == 0 && daysAdded.isEmpty && daysRemoved.isEmpty && periodsAdded.isEmpty && periodsRemoved.isEmpty && groupsChanged.isEmpty;
}

VersionDiff diffVersions(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b, {List<String>? daysA, List<String>? daysB, List<int>? periodsA, List<int>? periodsB}) {
  final ka = _byKey(a), kb = _byKey(b);
  final time = <(Map<String, dynamic>, Map<String, dynamic>)>[], room = <(Map<String, dynamic>, Map<String, dynamic>)>[], staff = <(Map<String, dynamic>, Map<String, dynamic>)>[];
  for (final k in ka.keys.where(kb.containsKey)) {
    final x = ka[k]!, y = kb[k]!;
    if (x['day'] != y['day'] || asInt(x['period_id']) != asInt(y['period_id'])) time.add((x, y));
    if (x['room_id'] != y['room_id']) room.add((x, y));
    if (x['teacher_id'] != y['teacher_id'] || x['assistant_id'] != y['assistant_id'] || x['admin_assistant_id'] != y['admin_assistant_id']) staff.add((x, y));
  }
  Map<String, int> groups(List<Map<String, dynamic>> s) {
    final g = <String, Set<int>>{};
    for (final x in s) {
      g.putIfAbsent('${x['course_id']}|${x['kind'] ?? 'lecture'}', () => {}).add(asInt(x['group_no'] ?? 1));
    }
    return g.map((k, v) => MapEntry(k, v.length));
  }

  final ga = groups(a), gb = groups(b);
  final dA = daysA ?? orgDays.where((d) => a.any((s) => s['day'] == d)).toList(), dB = daysB ?? orgDays.where((d) => b.any((s) => s['day'] == d)).toList();
  final pA = periodsA ?? {for (final s in a) asInt(s['period_id'])}.toList(), pB = periodsB ?? {for (final s in b) asInt(s['period_id'])}.toList();
  return VersionDiff(
    added: [for (final k in kb.keys) if (!ka.containsKey(k)) kb[k]!],
    removed: [for (final k in ka.keys) if (!kb.containsKey(k)) ka[k]!],
    timeChanged: time,
    roomChanged: room,
    staffChanged: staff,
    daysAdded: dB.where((d) => !dA.contains(d)).toList(),
    daysRemoved: dA.where((d) => !dB.contains(d)).toList(),
    periodsAdded: pB.where((p) => !pA.contains(p)).toList(),
    periodsRemoved: pA.where((p) => !pB.contains(p)).toList(),
    groupsChanged: {
      for (final k in {...ga.keys, ...gb.keys})
        if ((ga[k] ?? 0) != (gb[k] ?? 0)) k: (ga[k] ?? 0, gb[k] ?? 0)
    },
  );
}

/// A cheap fingerprint of a whole version: two alternatives with the same one are effectively identical.
String versionFingerprint(List<Map<String, dynamic>> slots) =>
    ([for (final s in slots) [s['course_id'], s['kind'] ?? 'lecture', s['group_no'] ?? 1, s['day'], s['period_id'], s['room_id'], s['teacher_id'], s['assistant_id']].join('|')]..sort()).join(';');

// ═════════════════════════════════════════════════════════════════════════════
//  Member copies
// ═════════════════════════════════════════════════════════════════════════════

const memberKinds = ['teacher', 'assistant', 'group', 'room'];

String memberKindLabel(String k) => switch (k) {
      'teacher' => t('مدرس', 'Teacher'),
      'assistant' => t('معيد', 'Teaching assistant'),
      'group' => t('مجموعة طلاب', 'Student group'),
      'room' => t('مكان', 'Room / lab'),
      _ => k,
    };

/// One member of a timetable. For a group [id] is the course id and [groupNo] / [kind] select the group.
class TimetableMember {
  const TimetableMember(this.kind, this.id, {this.groupNo, this.sessionKind});
  final String kind; // teacher · assistant · group · room
  final int id;
  final int? groupNo;
  final String? sessionKind; // lecture · lab (groups only)

  String get key => '$kind:$id:${groupNo ?? ''}:${sessionKind ?? ''}';

  bool has(Map<String, dynamic> s) => switch (kind) {
        'teacher' => s['teacher_id'] != null && asInt(s['teacher_id']) == id,
        'assistant' => (s['assistant_id'] != null && asInt(s['assistant_id']) == id) || (s['admin_assistant_id'] != null && asInt(s['admin_assistant_id']) == id),
        'group' => asInt(s['course_id']) == id && asInt(s['group_no'] ?? 1) == (groupNo ?? 1) && (s['kind'] ?? 'lecture') == (sessionKind ?? 'lecture'),
        'room' => s['room_id'] != null && asInt(s['room_id']) == id,
        _ => false,
      };

  @override
  bool operator ==(Object other) => other is TimetableMember && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Everyone who appears in [slots], by kind (teachers, assistants, groups, rooms).
List<TimetableMember> timetableMembers(List<Map<String, dynamic>> slots) {
  final out = <TimetableMember>{};
  for (final s in slots) {
    if (s['teacher_id'] != null) out.add(TimetableMember('teacher', asInt(s['teacher_id'])));
    for (final k in ['assistant_id', 'admin_assistant_id']) {
      if (s[k] != null) out.add(TimetableMember('assistant', asInt(s[k])));
    }
    if (s['course_id'] != null) out.add(TimetableMember('group', asInt(s['course_id']), groupNo: asInt(s['group_no'] ?? 1), sessionKind: '${s['kind'] ?? 'lecture'}'));
    if (s['room_id'] != null) out.add(TimetableMember('room', asInt(s['room_id'])));
  }
  return out.toList();
}

/// Only [m]'s sessions, in week order. [periodOrder] maps period id → its order in the day.
List<Map<String, dynamic>> memberTimetable(List<Map<String, dynamic>> slots, TimetableMember m, {Map<int, int> periodOrder = const {}}) =>
    sortSlots([for (final s in slots) if (m.has(s)) s], periodOrder: periodOrder);

List<Map<String, dynamic>> sortSlots(List<Map<String, dynamic>> slots, {Map<int, int> periodOrder = const {}}) {
  int day(Map s) => orgDays.indexOf('${s['day']}');
  int per(Map s) => periodOrder[asInt(s['period_id'])] ?? asInt(s['period_id']);
  return [...slots]..sort((a, b) => day(a) != day(b) ? day(a).compareTo(day(b)) : per(a).compareTo(per(b)));
}

/// A full copy is a stored revision. It is outdated as soon as the live timetable no longer matches it — copies are
/// never rewritten: a new copy is a new revision, and the old one stays as it was.
class TimetableCopy {
  const TimetableCopy({required this.id, required this.label, required this.createdAt, required this.source, this.version, this.slots = const [], this.summary = const {}, this.settings = const {}});

  final int id;
  final String label, source; // source: generate · manual · restore · suggest … as the server labels it
  final DateTime? createdAt;
  final int? version; // the timetable version it was taken at, when the server records it
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> summary, settings;

  factory TimetableCopy.fromJson(Map<String, dynamic> j) => TimetableCopy(
        id: asInt(j['id']),
        label: '${j['label'] ?? ''}',
        source: '${j['source'] ?? j['kind'] ?? ''}',
        createdAt: orgParseUtc(j['created_at']),
        version: asMap(j['summary'])['version'] == null ? null : asInt(asMap(j['summary'])['version']), // jobs.snapshot stores it in summary
        slots: asMapList(j['items']),
        summary: asMap(j['summary']),
        settings: asMap(j['settings']),
      );

  TimetableCopy withDetail(Map<String, dynamic> j) => TimetableCopy(
        id: id,
        label: label,
        source: source,
        createdAt: createdAt,
        version: version,
        slots: asMapList(j['items']),
        summary: asMap(j['summary']),
        settings: asMap(j['settings']),
      );

  /// null = cannot tell (details not loaded). A version number, when recorded, decides; otherwise the sessions do.
  bool? outdated({required int? liveVersion, required List<Map<String, dynamic>> liveSlots, bool detailLoaded = true}) {
    if (version != null && liveVersion != null) return version != liveVersion;
    if (!detailLoaded) return null;
    return versionFingerprint(slots) != versionFingerprint(liveSlots);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Export
// ═════════════════════════════════════════════════════════════════════════════

/// Names the export needs. Missing names fall back to "#id".
class TimetableNames {
  const TimetableNames({this.courses = const {}, this.people = const {}, this.rooms = const {}, this.periods = const {}});
  final Map<int, String> courses, people, rooms;
  final Map<int, Map<String, dynamic>> periods;

  String course(Object? id) => id == null ? '' : courses[asInt(id)] ?? '#$id';
  String person(Object? id) => id == null ? '' : people[asInt(id)] ?? '#$id';
  String room(Object? id) => id == null ? '' : rooms[asInt(id)] ?? '#$id';
}

/// Day names without depending on a widget tree (same labels as dayLabels()).
Map<String, String> dayLabelsPlain() => {
      'saturday': t('السبت', 'Saturday'),
      'sunday': t('الأحد', 'Sunday'),
      'monday': t('الاثنين', 'Monday'),
      'tuesday': t('الثلاثاء', 'Tuesday'),
      'wednesday': t('الأربعاء', 'Wednesday'),
      'thursday': t('الخميس', 'Thursday'),
      'friday': t('الجمعة', 'Friday'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Times of the timetable feature — every one goes through AppTime (12h / 24h + the organization's timezone)
// ═════════════════════════════════════════════════════════════════════════════

/// "HH:MM" wall clock of the organization (a period, a sitting) → "8:30 AM" / "08:30". Never converted.
String clockOf(Object? hhmm) => AppTime.clock(hhmm == null ? null : '$hhmm');

/// A period's or a sitting's time range: "8:00 – 9:30 AM".
String periodRange(Map<String, dynamic> p) => AppTime.clockRange(p['start_time'] as String?, p['end_time'] as String?);

/// A server timestamp (naive UTC ISO) → "23 Oct 2026 · 8:30 AM" in the effective zone; "—" when missing.
String stampOf(Object? iso) {
  final d = orgParseUtc(iso);
  return d == null ? '—' : AppTime.dateTime(d);
}

/// A calendar date ("2026-12-27", no time) → "Sun 27 Dec 2026" — never shifted by a timezone.
String calendarDate(Object? iso, {String pattern = 'EEE d MMM y'}) {
  final s = '${iso ?? ''}';
  final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
  if (d == null) return s.isEmpty ? '—' : s;
  AppTime.toZone(DateTime.utc(2000)); // loads the date-symbol data (Arabic month names)
  try {
    return DateFormat(pattern, AppConfig.lang).format(d);
  } catch (_) {
    return DateFormat(pattern).format(d);
  }
}
