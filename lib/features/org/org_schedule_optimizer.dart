// lib/features/org/org_schedule_optimizer.dart — improvement suggestions (shown as last-resort advice in the generation
// result, org_schedule_generate.dart) and the scheduling horizon (days / periods policy).
//
//   ScheduleHealth        pure: dashboard numbers from GET …/validate, the generation report and the suggestions
//   ScheduleSuggestion    one proposed change set (move / add period / add day / rooms / groups / staff / combined)
//   SuggestionApi         Remote (…/schedules/{sid}/suggestions, routers/organization/org_schedule_router.py) · Mock (dev only)
//                         accepting a day / period / groups change answers 202 + a regeneration run, followed to its end
//   ScheduleHorizon       settings.horizon — flexible (suggest, needs approval) or forced (admin sets the days)
//
// Every number shown comes from the server (validate, schedule.result, suggestions) or from the development mock,
// which is labelled as such. Nothing is estimated here: when the server sends no explanation, none is shown.
// Undo of an applied suggestion is the existing revision restore (POST …/revisions/{id}/restore).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart';
import 'org_schedule_planning.dart' show kOrgSchedulingMocks;
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

const suggestionTypes = ['reschedule_session', 'add_period', 'add_day', 'add_room', 'reallocate_groups', 'reassign_staff', 'combined', 'add_staff'];
const suggestionStatuses = ['pending', 'accepted', 'applied', 'rejected', 'invalidated', 'failed'];

String _bi(Map<String, dynamic> j, String key) {
  final ar = j['${key}_ar'], en = j['${key}_en'];
  if (ar == null && en == null) return '${j[key] ?? ''}';
  return t('${ar ?? en}', '${en ?? ar}');
}

/// One slot-level edit inside a suggestion. `before` / `after` hold the slot fields that change.
class SuggestionChange {
  const SuggestionChange({required this.op, this.slotId, this.courseId, this.kind, this.groupNo, this.before = const {}, this.after = const {}, this.reason = ''});
  final String op; // move | assign_room | assign_staff | add | remove
  final int? slotId, courseId, groupNo;
  final String? kind; // lecture | lab
  final Map<String, dynamic> before, after;
  final String reason; // per-change explanation from the server (empty when none)

  factory SuggestionChange.fromJson(Map<String, dynamic> j) => SuggestionChange(
        op: '${j['op'] ?? 'move'}',
        slotId: j['slot_id'] == null ? null : asInt(j['slot_id']),
        courseId: j['course_id'] == null ? null : asInt(j['course_id']),
        kind: j['kind'] as String?,
        groupNo: j['group_no'] == null ? null : asInt(j['group_no']),
        before: asMap(j['before']),
        after: asMap(j['after']),
        reason: _bi(j, 'reason'),
      );
}

class SuggestionImpact {
  const SuggestionImpact({this.resolved, this.introduced, this.remaining, this.conflictsBefore, this.conflictsAfter, this.unscheduledBefore, this.unscheduledAfter, this.softCostBefore, this.softCostAfter});
  final int? resolved, introduced, remaining, conflictsBefore, conflictsAfter, unscheduledBefore, unscheduledAfter;
  final num? softCostBefore, softCostAfter;

  factory SuggestionImpact.fromJson(Map<String, dynamic> j) {
    int? i(String k) => j[k] == null ? null : asInt(j[k]);
    num? n(String k) => j[k] is num ? j[k] as num : null;
    return SuggestionImpact(
      resolved: i('resolved_conflicts'),
      introduced: i('introduced_conflicts'),
      remaining: i('remaining_conflicts'),
      conflictsBefore: i('conflicts_before'),
      conflictsAfter: i('conflicts_after'),
      unscheduledBefore: i('unscheduled_before'),
      unscheduledAfter: i('unscheduled_after'),
      softCostBefore: n('soft_cost_before'),
      softCostAfter: n('soft_cost_after'),
    );
  }
}

class ScheduleSuggestion {
  const ScheduleSuggestion({
    required this.id,
    required this.type,
    this.scheduleId = 0,
    this.status = 'pending',
    this.title = '',
    this.reason = '',
    this.baseVersion,
    this.affected = const [],
    this.changes = const [],
    this.config = const {},
    this.impact = const SuggestionImpact(),
    this.introducedConflicts = const [],
    this.valid,
    this.violations = const [],
    this.permission = 'schedule.update',
    this.needsApproval = false,
    this.applicable = true,
    this.decisionReason,
    this.revisionBeforeId,
    this.error,
  });

  final String id, type, status, title, reason, permission;
  final int scheduleId;
  final int? baseVersion; // timetable version the suggestion was computed (and last validated) against
  final List<Map<String, dynamic>> affected; // [{type: course|group|teacher|assistant|room|period|day|students, id, label}]
  final List<SuggestionChange> changes;
  final Map<String, dynamic> config; // days / periods / rooms / groups — {before, after, …}
  final SuggestionImpact impact;
  final List<Map<String, dynamic>> introducedConflicts, violations; // described conflicts (text_ar / text_en)
  final bool? valid; // null = the server has not validated it
  final bool needsApproval;
  final bool applicable; // false = advice only (e.g. open a new lab): it can be rejected, never applied
  final String? decisionReason, error;
  final int? revisionBeforeId; // set once applied: restoring it undoes the suggestion

  factory ScheduleSuggestion.fromJson(Map<String, dynamic> j) {
    final v = asMap(j['validation']), req = asMap(j['requires']), dec = asMap(j['decision']), res = asMap(j['result']);
    return ScheduleSuggestion(
      id: '${j['suggestion_id'] ?? j['id']}',
      scheduleId: asInt(j['schedule_id']),
      type: '${j['type'] ?? ''}',
      status: suggestionStatuses.contains(j['status']) ? j['status'] as String : 'pending',
      title: _bi(j, 'title'),
      reason: _bi(j, 'reason'),
      baseVersion: j['base_version'] == null ? null : asInt(j['base_version']),
      affected: asMapList(j['affected']),
      changes: asMapList(j['changes']).map(SuggestionChange.fromJson).toList(),
      config: asMap(j['config']),
      impact: SuggestionImpact.fromJson(asMap(j['impact'])),
      introducedConflicts: asMapList(j['introduced_conflicts']),
      valid: v['valid'] is bool ? v['valid'] as bool : null,
      // the server sends the violated rule types as strings; described conflicts are maps
      violations: [for (final x in (v['hard_constraint_violations'] as List?) ?? const []) x is Map ? Map<String, dynamic>.from(x) : {'type': '$x', 'severity': 'error'}],
      permission: '${req['permission'] ?? 'schedule.update'}',
      needsApproval: req['approval'] == true,
      applicable: j['applicable'] != false,
      decisionReason: dec['reason'] as String?,
      revisionBeforeId: res['revision_before_id'] == null ? null : asInt(res['revision_before_id']),
      error: res['error'] as String?,
    );
  }

  ScheduleSuggestion copyWith({String? status, String? decisionReason, int? revisionBeforeId}) => ScheduleSuggestion(
        id: id,
        type: type,
        scheduleId: scheduleId,
        status: status ?? this.status,
        title: title,
        reason: reason,
        baseVersion: baseVersion,
        affected: affected,
        changes: changes,
        config: config,
        impact: impact,
        introducedConflicts: introducedConflicts,
        valid: valid,
        violations: violations,
        permission: permission,
        needsApproval: needsApproval,
        applicable: applicable,
        decisionReason: decisionReason ?? this.decisionReason,
        revisionBeforeId: revisionBeforeId ?? this.revisionBeforeId,
        error: error,
      );

  /// Computed against another version of the timetable — the server must revalidate before applying it.
  bool isStale(int? currentVersion) => baseVersion != null && currentVersion != null && baseVersion != currentVersion;

  /// Changes the scheduling horizon (days / periods) or the facilities, not only sessions.
  bool get expandsConfig => config.isNotEmpty;

  /// Used by the mock to avoid proposing a rejected suggestion again while nothing changed.
  String get fingerprint => '$type|${changes.map((c) => '${c.slotId}:${c.after}').join(',')}|$config';
}

class SuggestionList {
  const SuggestionList(this.items, {this.version, this.unsupported = false, this.mock = false});
  final List<ScheduleSuggestion> items;
  final int? version;
  final bool unsupported; // the server has no suggestions route yet
  final bool mock;
}

/// Result of accept / batch apply.
class SuggestionApplied {
  const SuggestionApplied(this.items, {this.version, this.revisionId, this.run});
  final List<ScheduleSuggestion> items;
  final int? version, revisionId;

  /// A configuration change (day / period / groups) answers 202 with the regeneration run: the suggestion stays
  /// "accepted" until that run ends and marks it applied or failed.
  final Map<String, dynamic>? run;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Dashboard numbers (pure)
// ═════════════════════════════════════════════════════════════════════════════

class ScheduleHealth {
  const ScheduleHealth({
    required this.hard,
    required this.warnings,
    required this.soft,
    required this.byType,
    required this.unscheduledLectures,
    required this.unscheduledLabs,
    required this.suggestions,
    required this.resolvedByApplied,
    this.resultStatus,
    this.sessionsRequired,
    this.sessionsPlaced,
    this.softCost,
    this.requiredChanges = const [],
  });

  final int hard, warnings, soft; // current conflicts by severity (validate)
  final Map<String, int> byType; // conflict type → count, hard + warnings
  final int unscheduledLectures, unscheduledLabs; // sessions the last generation could not place
  final Map<String, int> suggestions; // status → count
  final int? resolvedByApplied; // sum of resolved_conflicts of applied suggestions; null when none reported it
  final String? resultStatus;
  final int? sessionsRequired, sessionsPlaced;
  final num? softCost;
  final List<String> requiredChanges; // what still blocks a valid timetable, in the server's words

  int get remaining => hard + warnings;
  int get total => remaining + (resolvedByApplied ?? 0);
  int get unscheduled => unscheduledLectures + unscheduledLabs;
  bool get valid => hard == 0 && unscheduled == 0;

  /// Placed / required — only when the generation report gives both. Null otherwise (never guessed).
  double? get placementRate => sessionsRequired == null || sessionsPlaced == null || sessionsRequired == 0 ? null : sessionsPlaced! / sessionsRequired!;

  factory ScheduleHealth.from({required List<Map<String, dynamic>> conflicts, required Map<String, dynamic> result, List<ScheduleSuggestion> suggestions = const []}) {
    int sev(String s) => conflicts.where((x) => x['severity'] == s).length;
    final byType = <String, int>{};
    for (final x in conflicts.where((x) => x['severity'] != 'soft')) {
      byType['${x['type']}'] = (byType['${x['type']}'] ?? 0) + 1;
    }
    var lec = 0, lab = 0;
    for (final u in asMapList(result['unscheduled'])) {
      final n = asInt(u['missing'], 1);
      u['kind'] == 'lab' ? lab += n : lec += n;
    }
    final counts = <String, int>{for (final s in suggestionStatuses) s: 0};
    int? resolved;
    for (final s in suggestions) {
      counts[s.status] = (counts[s.status] ?? 0) + 1;
      if (s.status == 'applied' && s.impact.resolved != null) resolved = (resolved ?? 0) + s.impact.resolved!;
    }
    final stats = asMap(result['stats']);
    String text(String type) {
      final s = _bi(conflicts.firstWhere((x) => '${x['type']}' == type), 'text');
      return s.isEmpty ? type : s;
    }

    final changes = <String>[
      for (final e in byType.entries) '${text(e.key)} × ${e.value}',
      for (final s in asMapList(result['suggestions']))
        if ('${s['text'] ?? ''}'.isNotEmpty) '${s['text']}${s['sessions'] == null ? '' : ' (${s['sessions']})'}',
    ];
    return ScheduleHealth(
      hard: sev('error'),
      warnings: sev('warning'),
      soft: sev('soft'),
      byType: byType,
      unscheduledLectures: lec,
      unscheduledLabs: lab,
      suggestions: counts,
      resolvedByApplied: resolved,
      resultStatus: result['status'] as String?,
      sessionsRequired: stats['sessions_required'] == null ? null : asInt(stats['sessions_required']),
      sessionsPlaced: stats['sessions_placed'] == null ? null : asInt(stats['sessions_placed']),
      softCost: stats['soft_cost'] is num ? stats['soft_cost'] as num : null,
      requiredChanges: changes,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Horizon (settings.horizon)
// ═════════════════════════════════════════════════════════════════════════════

class ScheduleHorizon {
  const ScheduleHorizon({this.mode = 'flexible', this.minDays = 1, this.maxDays = 7, this.maxPeriods, this.allowExpansion = true, this.autoApplyApproved = false});
  final String mode; // flexible: the system may PROPOSE more days / periods (approval needed) · forced: the admin sets them
  final int minDays, maxDays;
  final int? maxPeriods; // periods per day the organization may grow to; null = no limit set
  final bool allowExpansion; // may suggestions propose extra days / periods at all
  final bool autoApplyApproved; // an approved expansion is applied at once instead of waiting for a second step

  factory ScheduleHorizon.fromSettings(Map<String, dynamic> settings) {
    final h = asMap(settings['horizon']);
    return ScheduleHorizon(
      mode: h['mode'] == 'forced' ? 'forced' : 'flexible',
      minDays: asInt(h['min_days'], 1).clamp(1, 7),
      maxDays: asInt(h['max_days'], 7).clamp(1, 7),
      maxPeriods: h['max_periods_per_day'] == null ? null : asInt(h['max_periods_per_day']),
      allowExpansion: h['allow_expansion'] != false,
      autoApplyApproved: h['auto_apply_approved'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'min_days': minDays,
        'max_days': maxDays,
        'max_periods_per_day': maxPeriods,
        'allow_expansion': allowExpansion,
        'auto_apply_approved': autoApplyApproved,
      };

  ScheduleHorizon copyWith({String? mode, int? minDays, int? maxDays, int? Function()? maxPeriods, bool? allowExpansion, bool? autoApplyApproved}) => ScheduleHorizon(
        mode: mode ?? this.mode,
        minDays: minDays ?? this.minDays,
        maxDays: maxDays ?? this.maxDays,
        maxPeriods: maxPeriods == null ? this.maxPeriods : maxPeriods(),
        allowExpansion: allowExpansion ?? this.allowExpansion,
        autoApplyApproved: autoApplyApproved ?? this.autoApplyApproved,
      );

  /// Null when [days] study days and [periods] periods per day fit the policy; otherwise the reason.
  String? check(int days, int periods) {
    if (minDays > maxDays) return t('الحد الأدنى للأيام أكبر من الأقصى', 'The minimum days exceed the maximum');
    if (days < minDays || days > maxDays) return t('عدد الأيام ($days) خارج الحدود $minDays–$maxDays', 'Study days ($days) outside $minDays–$maxDays');
    if (maxPeriods != null && periods > maxPeriods!) return t('عدد الفترات ($periods) أكبر من الحد $maxPeriods', 'Periods per day ($periods) above the limit $maxPeriods');
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

abstract class SuggestionApi {
  Future<SuggestionList> list(int scheduleId);

  /// Asks the server for fresh suggestions for the timetable as it is at [version].
  Future<SuggestionList> generate(int scheduleId, {required int? version, List<String>? types});

  /// The server revalidates against the latest timetable, applies and writes a revision. Throws [ApiException]:
  /// suggestion_stale · stale_version · suggestion_invalid (detail.conflicts) · suggestion_not_pending · 403.
  Future<SuggestionApplied> accept(int scheduleId, String id, {required int? version});

  Future<ScheduleSuggestion> reject(int scheduleId, String id, {String? reason});

  /// All or nothing: every suggestion is revalidated together, then applied in one revision.
  Future<SuggestionApplied> applyBatch(int scheduleId, List<String> ids, {required int? version});
}

class RemoteSuggestionApi implements SuggestionApi {
  RemoteSuggestionApi(this.api, this.base);
  final ApiClient api;
  final String base; // /orgs/{id}

  String _p(int sid) => '$base/schedules/$sid/suggestions';

  static SuggestionList _list(dynamic r) {
    final m = asMap(r);
    return SuggestionList(asMapList(m['items']).map(ScheduleSuggestion.fromJson).toList(), version: m['version'] == null ? null : asInt(m['version']));
  }

  static SuggestionApplied _applied(dynamic r) {
    final m = asMap(r);
    final items = m['items'] is List ? asMapList(m['items']) : [asMap(m['suggestion'])];
    return SuggestionApplied(items.where((x) => x.isNotEmpty).map(ScheduleSuggestion.fromJson).toList(),
        version: m['version'] == null ? null : asInt(m['version']),
        revisionId: asMap(m['revision'])['id'] == null ? null : asInt(asMap(m['revision'])['id']),
        run: m['run'] is Map ? asMap(m['run']) : null);
  }

  @override
  Future<SuggestionList> list(int scheduleId) async {
    try {
      return _list(await api.get(_p(scheduleId)));
    } catch (e) {
      final err = ApiException.from(e);
      if (orgEndpointMissing(err)) return const SuggestionList([], unsupported: true);
      rethrow;
    }
  }

  @override
  Future<SuggestionList> generate(int scheduleId, {required int? version, List<String>? types}) async =>
      _list(await api.post(_p(scheduleId), body: {'expected_version': version, 'types': ?types}));

  @override
  Future<SuggestionApplied> accept(int scheduleId, String id, {required int? version}) async =>
      _applied(await api.post('${_p(scheduleId)}/$id/accept', body: {'expected_version': version}));

  @override
  Future<ScheduleSuggestion> reject(int scheduleId, String id, {String? reason}) async =>
      ScheduleSuggestion.fromJson(asMap(await api.post('${_p(scheduleId)}/$id/reject', body: {'reason': reason})));

  @override
  Future<SuggestionApplied> applyBatch(int scheduleId, List<String> ids, {required int? version}) async =>
      _applied(await api.post('${_p(scheduleId)}/apply', body: {'ids': ids, 'expected_version': version}));
}

/// What the mock builds its suggestions from: the provider's real, current data.
class SuggestionContext {
  const SuggestionContext({required this.version, this.conflicts = const [], this.slots = const [], this.days = const [], this.periodIds = const [], this.unscheduled = 0});
  final int? version;
  final List<Map<String, dynamic>> conflicts, slots;
  final List<String> days;
  final List<int> periodIds;
  final int unscheduled;
}

/// In-memory stand-in for development. It never edits the timetable: "applied" only changes the suggestion's status.
class MockSuggestionApi implements SuggestionApi {
  MockSuggestionApi(this.source);
  final SuggestionContext Function(int scheduleId) source;
  final _store = <int, List<ScheduleSuggestion>>{};
  final _rejected = <int, Set<String>>{}; // fingerprints rejected at the version they were seen
  var _n = 0;

  ApiException _err(int status, String code, String msg) => ApiException(statusCode: status, message: msg, code: code);

  @override
  Future<SuggestionList> list(int scheduleId) async => SuggestionList(List.of(_store[scheduleId] ?? const []), version: source(scheduleId).version, mock: true);

  @override
  Future<SuggestionList> generate(int scheduleId, {required int? version, List<String>? types}) async {
    final ctx = source(scheduleId);
    if (version != ctx.version) throw _err(409, 'stale_version', 'stale');
    final keep = [for (final s in _store[scheduleId] ?? const <ScheduleSuggestion>[]) if (s.status != 'pending') s];
    final fresh = <ScheduleSuggestion>[];
    final busy = {for (final s in ctx.slots) '${s['day']}|${s['period_id']}'};
    for (final x in ctx.conflicts.where((x) => x['severity'] == 'error').take(3)) {
      final sid = (x['removable_slot_ids'] as List? ?? const []).map(asInt).firstOrNull;
      final slot = ctx.slots.where((s) => asInt(s['id']) == sid).firstOrNull;
      if (slot == null) continue;
      final free = [for (final d in ctx.days) for (final p in ctx.periodIds) if (!busy.contains('$d|$p')) (d, p)].firstOrNull;
      if (free == null) continue;
      busy.add('${free.$1}|${free.$2}');
      fresh.add(ScheduleSuggestion(
        id: 'mock-${++_n}',
        scheduleId: scheduleId,
        type: 'reschedule_session',
        title: t('نقل الحصة إلى خانة فارغة', 'Move the session to an empty cell'),
        reason: _bi(x, 'text'),
        baseVersion: ctx.version,
        affected: [if (slot['course_id'] != null) {'type': 'course', 'id': slot['course_id']}],
        changes: [
          SuggestionChange(op: 'move', slotId: sid, courseId: asInt(slot['course_id']), before: {'day': slot['day'], 'period_id': slot['period_id']}, after: {'day': free.$1, 'period_id': free.$2})
        ],
        impact: const SuggestionImpact(resolved: 1, introduced: 0),
        valid: true,
      ));
    }
    if (ctx.unscheduled > 0 && ctx.days.length < 7) {
      final next = scheduleDays.firstWhere((d) => !ctx.days.contains(d));
      fresh.add(ScheduleSuggestion(
        id: 'mock-${++_n}',
        scheduleId: scheduleId,
        type: 'add_day',
        title: t('إضافة يوم دراسي', 'Add a study day'),
        baseVersion: ctx.version,
        config: {
          'days': {'before': ctx.days, 'after': [...ctx.days, next]}
        },
        impact: SuggestionImpact(unscheduledBefore: ctx.unscheduled),
        needsApproval: true,
        permission: 'schedule.approve',
      ));
    }
    if (ctx.unscheduled > 0) {
      fresh.add(ScheduleSuggestion(
        id: 'mock-${++_n}',
        scheduleId: scheduleId,
        type: 'add_period',
        title: t('إضافة فترة يومية', 'Add a daily period'),
        baseVersion: ctx.version,
        config: {
          'periods': {'before': ctx.periodIds.length, 'after': ctx.periodIds.length + 1}
        },
        impact: SuggestionImpact(unscheduledBefore: ctx.unscheduled),
        needsApproval: true,
        permission: 'schedule.approve',
      ));
    }
    final rejected = _rejected[scheduleId] ?? const {};
    final out = [
      ...keep,
      for (final s in fresh)
        if ((types == null || types.contains(s.type)) && !rejected.contains('${ctx.version}|${s.fingerprint}') && !keep.any((k) => k.status != 'rejected' && k.fingerprint == s.fingerprint)) s
    ];
    _store[scheduleId] = out;
    return SuggestionList(List.of(out), version: ctx.version, mock: true);
  }

  ScheduleSuggestion _find(int sid, String id) =>
      (_store[sid] ?? const <ScheduleSuggestion>[]).where((s) => s.id == id).firstOrNull ?? (throw _err(404, 'suggestion_not_found', 'not found'));

  void _put(int sid, ScheduleSuggestion s) => _store[sid] = [for (final x in _store[sid]!) x.id == s.id ? s : x];

  void _check(int sid, ScheduleSuggestion s, int? version) {
    if (s.status == 'applied') throw _err(409, 'suggestion_already_applied', 'already applied');
    if (s.status != 'pending') throw _err(409, 'suggestion_not_pending', 'not pending');
    if (version != source(sid).version) throw _err(409, 'stale_version', 'stale');
    if (s.isStale(version)) throw _err(409, 'suggestion_stale', 'stale suggestion');
    if (s.valid == false) throw _err(422, 'suggestion_invalid', 'invalid');
  }

  @override
  Future<SuggestionApplied> accept(int scheduleId, String id, {required int? version}) async {
    final s = _find(scheduleId, id);
    _check(scheduleId, s, version);
    final done = s.copyWith(status: 'applied');
    _put(scheduleId, done);
    return SuggestionApplied([done], version: version);
  }

  @override
  Future<ScheduleSuggestion> reject(int scheduleId, String id, {String? reason}) async {
    final s = _find(scheduleId, id);
    if (s.status != 'pending') throw _err(409, 'suggestion_not_pending', 'not pending');
    final done = s.copyWith(status: 'rejected', decisionReason: reason);
    _put(scheduleId, done);
    (_rejected[scheduleId] ??= {}).add('${source(scheduleId).version}|${s.fingerprint}');
    return done;
  }

  @override
  Future<SuggestionApplied> applyBatch(int scheduleId, List<String> ids, {required int? version}) async {
    final all = [for (final id in ids) _find(scheduleId, id)];
    for (final s in all) {
      _check(scheduleId, s, version); // nothing changes unless every one passes
    }
    final slots = <int>{};
    for (final s in all) {
      for (final c in s.changes) {
        if (c.slotId != null && !slots.add(c.slotId!)) throw _err(409, 'suggestions_overlap', 'two suggestions move the same session');
      }
    }
    final done = [for (final s in all) s.copyWith(status: 'applied')];
    for (final s in done) {
      _put(scheduleId, s);
    }
    return SuggestionApplied(done, version: version);
  }
}

MockSuggestionApi? _mock;

SuggestionApi suggestionApi(OrgScheduleProvider p) {
  if (!kOrgSchedulingMocks) return RemoteSuggestionApi(p.api, p.base);
  return _mock ??= MockSuggestionApi((sid) {
    final sch = p.schedule ?? const {};
    final days = ScheduleDraft.fromJson(sch).days;
    return SuggestionContext(
      version: sch['version'] == null ? null : asInt(sch['version']),
      conflicts: p.conflicts,
      slots: p.slots,
      days: days,
      periodIds: [for (final x in p.periods) asInt(x['id'])],
      unscheduled: ScheduleHealth.from(conflicts: const [], result: asMap(sch['result'])).unscheduled,
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

String suggestionTypeLabel(String type) => switch (type) {
      'reschedule_session' => t('نقل حصة', 'Reschedule a session'),
      'add_period' => t('إضافة فترة', 'Add a period'),
      'add_day' => t('إضافة يوم', 'Add a study day'),
      'add_room' => t('مكان إضافي', 'Add / reconfigure rooms'),
      'reallocate_groups' => t('إعادة توزيع المجموعات', 'Reallocate groups'),
      'reassign_staff' => t('تغيير المدرس / المعيد', 'Reassign staff'),
      'add_staff' => t('إضافة عضو جديد', 'Add a new member'),
      'combined' => t('تغييرات مجمّعة', 'Combined changes'),
      _ => type,
    };

IconData suggestionTypeIcon(String type) => switch (type) {
      'reschedule_session' => Icons.open_with_rounded,
      'add_period' => Icons.more_time_rounded,
      'add_day' => Icons.calendar_month_rounded,
      'add_room' => Icons.meeting_room_rounded,
      'reallocate_groups' => Icons.workspaces_rounded,
      'reassign_staff' => Icons.swap_horiz_rounded,
      'add_staff' => Icons.person_add_alt_1_rounded,
      _ => Icons.auto_fix_high_rounded,
    };

/// What the suggestion keeps and what it gives up, from the server's own validation and soft-cost figures.
String suggestionTradeOff(ScheduleSuggestion s) {
  final i = s.impact;
  final kept = s.valid == true
      ? t('القيود الإلزامية محفوظة (الأهلية، السعة، التجهيزات، عدم التداخل، الأوقات غير المتاحة)', 'Hard rules kept (eligibility, capacity, facilities, no double booking, unavailable times)')
      : s.valid == false
          ? t('يخالف قيداً إلزامياً — لا يمكن تطبيقه', 'Breaks a hard rule — it cannot be applied')
          : t('لم يتحقق الخادم من القيود بعد', 'The server has not checked the rules yet');
  final before = i.softCostBefore, after = i.softCostAfter;
  final soft = before == null || after == null
      ? ''
      : after > before
          ? t(' · يخفّف تفضيلات مرنة (التكلفة +${(after - before).toStringAsFixed(1)})', ' · relaxes soft preferences (cost +${(after - before).toStringAsFixed(1)})')
          : t(' · لا يخفّف أي تفضيل مرن', ' · relaxes no soft preference');
  final config = s.expandsConfig ? t(' · يغيّر إعداد الجدول نفسه ويعيد توليد الحصص المتأثرة', ' · changes the timetable set-up itself and regenerates the affected sessions') : '';
  return '$kept$soft$config';
}

String suggestionStatusLabel(String s) => switch (s) {
      'pending' => t('مقترح', 'Suggested'),
      'accepted' => t('مقبول — جارٍ التطبيق', 'Accepted — applying'),
      'applied' => t('طُبّق', 'Applied'),
      'rejected' => t('مرفوض', 'Rejected'),
      'invalidated' => t('لم يعد صالحاً', 'Invalidated'),
      'failed' => t('فشل التطبيق', 'Failed'),
      _ => s,
    };

