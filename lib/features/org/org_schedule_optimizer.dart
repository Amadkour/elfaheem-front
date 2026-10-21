// lib/features/org/org_schedule_optimizer.dart — the timetable's health dashboard, improvement suggestions and
// scheduling horizon (days / periods policy).
//
//   ScheduleHealth        pure: dashboard numbers from GET …/validate, the generation report and the suggestions
//   ScheduleSuggestion    one proposed change set (move / add period / add day / rooms / groups / staff / combined)
//   SuggestionApi         Remote (…/schedules/{sid}/suggestions, routers/organization/org_schedule_router.py) · Mock (dev only)
//                         accepting a day / period / groups change answers 202 + a regeneration run, followed to its end
//   ScheduleHorizon       settings.horizon — flexible (suggest, needs approval) or forced (admin sets the days)
//   openScheduleOptimizer the page, opened from the timetable studio
//
// Every number shown comes from the server (validate, schedule.result, suggestions) or from the development mock,
// which is labelled as such. Nothing is estimated here: when the server sends no explanation, none is shown.
// Undo of an applied suggestion is the existing revision restore (POST …/revisions/{id}/restore).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_planning.dart' show kOrgSchedulingMocks;
import 'org_schedule_versions.dart';
import 'org_ui.dart';
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

const suggestionTypes = ['reschedule_session', 'add_period', 'add_day', 'add_room', 'reallocate_groups', 'reassign_staff', 'combined'];
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

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

Future<void> openScheduleOptimizer(BuildContext context, OrgScheduleProvider p, {bool canEdit = false, bool canApprove = false}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BasePage(
              useWebCard: true,
              maxWith: 1000,
              appBar: ScreenAppBar(title: t('تحسين الجدول', 'Optimize the timetable')),
              child: _OptimizerPage(p: p, api: suggestionApi(p), canEdit: canEdit, canApprove: canApprove),
            )));

class _OptimizerPage extends StatefulWidget {
  const _OptimizerPage({required this.p, required this.api, required this.canEdit, required this.canApprove});
  final OrgScheduleProvider p;
  final SuggestionApi api;
  final bool canEdit, canApprove;

  @override
  State<_OptimizerPage> createState() => _OptimizerPageState();
}

class _OptimizerPageState extends State<_OptimizerPage> {
  SuggestionList? data;
  String? error;
  bool generating = false;
  String filter = 'pending';
  final busy = <String>{}; // suggestion ids in flight — a second tap never sends a second apply
  final applying = <String>{}; // accepted, regeneration running
  final picked = <String>{};

  OrgScheduleProvider get p => widget.p;
  int get sid => asInt(p.schedule?['id']);
  int? get version => p.schedule?['version'] == null ? null : asInt(p.schedule!['version']);
  bool get draft => p.schedule?['status'] != 'active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final r = await widget.api.list(sid);
      if (mounted) setState(() => data = r);
    } catch (e) {
      if (mounted) setState(() => error = orgErrorText(ApiException.from(e)));
    }
  }

  Future<void> _refreshAll() async {
    await p.open(sid); // timetable + validate
    await _load();
  }

  Future<void> _generate() async {
    setState(() => generating = true);
    try {
      final r = await widget.api.generate(sid, version: version);
      if (mounted) setState(() => data = r);
    } catch (e) {
      final x = ApiException.from(e);
      toast(orgEndpointMissing(x) ? t('الخادم لا يدعم الاقتراحات بعد', 'The server cannot suggest changes yet') : orgErrorText(x), error: true);
      if (x.code == 'stale_version') await _refreshAll();
    }
    if (mounted) setState(() => generating = false);
  }

  /// Accept one (or apply the picked batch). The server revalidates; a stale or now-invalid proposal is never forced.
  Future<void> _apply(List<ScheduleSuggestion> items) async {
    final ids = [for (final s in items) s.id];
    if (ids.any(busy.contains)) return;
    final config = items.where((s) => s.expandsConfig).toList();
    if (config.isNotEmpty && !await _confirmExpansion(config)) return;
    setState(() => busy.addAll(ids));
    try {
      final r = ids.length == 1 ? await widget.api.accept(sid, ids.single, version: version) : await widget.api.applyBatch(sid, ids, version: version);
      picked.removeAll(ids);
      if (r.run != null) {
        // a configuration change: success is only reported once the regeneration has run and the server says so
        setState(() => applying.addAll(ids));
        await _follow(r.run!);
        setState(() => applying.removeAll(ids));
      }
      await _refreshAll();
      final now = [for (final s in data?.items ?? const <ScheduleSuggestion>[]) if (ids.contains(s.id)) s];
      final failed = now.where((s) => s.status == 'failed' || s.status == 'invalidated').length;
      final open = now.where((s) => s.status == 'accepted').length;
      toast(
          failed > 0
              ? t('تعذّر تطبيق $failed من الاقتراحات — لم يتغير شيء منها، راجع السبب', '$failed suggestion(s) could not be applied — nothing of them changed, see why')
              : open > 0
                  ? t('قُبل — إعادة التوليد ما زالت تعمل', 'Accepted — the regeneration is still running')
                  : t('طُبّق التغيير على الجدول وحُفظت نسخة', 'Applied to the timetable — a version was saved'),
          error: failed > 0);
    } catch (e) {
      final x = ApiException.from(e);
      if (x.code == 'suggestion_invalid' && mounted) {
        await _showConflicts(t('لم يعد الاقتراح صالحاً', 'The suggestion is no longer valid'), asMapList(asMap(ApiException.asMap(x.body)?['detail'])['conflicts']));
      } else {
        toast(orgErrorText(x), error: true);
      }
      if (x.code == 'stale_version' || x.code == 'suggestion_stale' || x.code == 'suggestion_invalid' || x.code == 'suggestion_already_applied') await _refreshAll();
    }
    if (mounted) setState(() => busy.removeAll(ids));
  }

  /// Follows the regeneration an accepted configuration change started (GET …/runs/{id}) until it ends.
  Future<void> _follow(Map<String, dynamic> run) async {
    var r = run;
    final rid = asInt(r['id']);
    for (var i = 0; i < 300 && runIsOpen(r) && mounted; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final g = await orgCall(() => p.api.get('${p.base}/schedules/$sid/runs/$rid'), quiet: true);
      if (g.ok) r = g.map;
    }
  }

  Future<void> _reject(ScheduleSuggestion s) async {
    final reason = TextEditingController();
    final ok = await showAdminSheet<bool>(context, (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('رفض الاقتراح', 'Reject the suggestion')),
            TextField(controller: reason, maxLength: 255, decoration: InputDecoration(labelText: t('السبب (اختياري)', 'Reason (optional)'))),
            const SizedBox(height: 8),
            PrimaryButton(isLoading: false, label: t('رفض', 'Reject'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true || busy.contains(s.id)) return;
    setState(() => busy.add(s.id));
    try {
      final r = await widget.api.reject(sid, s.id, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      if (mounted) setState(() => data = SuggestionList([for (final x in data!.items) x.id == r.id ? r : x], version: data!.version, mock: data!.mock));
    } catch (e) {
      toast(orgErrorText(ApiException.from(e)), error: true);
    }
    if (mounted) setState(() => busy.remove(s.id));
  }

  Future<void> _undo(ScheduleSuggestion s) async {
    if (!await confirm(context, message: t('استرجاع الجدول كما كان قبل هذا التغيير؟ تُحفظ نسخة جديدة ولا يُحذف شيء.', 'Restore the timetable as it was before this change? A new version is saved; nothing is deleted.'))) return;
    if (await p.restoreRevision(s.revisionBeforeId!)) await _load();
  }

  Future<bool> _confirmExpansion(List<ScheduleSuggestion> items) async =>
      await showAdminSheet<bool>(context, (ctx) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('تغيير إعداد الجدول', 'Change the timetable set-up')),
            for (final s in items) ...[
              Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, style: orgText(ctx, w: FontWeight.w800)),
              ..._configLines(ctx, s.config).map((l) => Text('• $l', style: orgText(ctx, size: 12.5))),
              _impactLine(ctx, s.impact),
              if (s.affected.isNotEmpty) Text(t('حصص متأثرة: ${s.affected.length}', 'Affected: ${s.affected.length}'), style: orgText(ctx, size: 12, color: c.textMedium)),
              const SizedBox(height: 10),
            ],
            Text(t('القيود الإلزامية تبقى مطبّقة. الخادم يعيد التحقق قبل التطبيق.', 'Hard rules still apply. The server revalidates before applying.'), style: orgText(ctx, size: 12, color: c.textMedium)),
            const SizedBox(height: 10),
            PrimaryButton(isLoading: false, label: t('موافقة وتطبيق', 'Approve and apply'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        );
      }) ==
      true;

  Future<void> _showConflicts(String title, List<Map<String, dynamic>> conflicts) => showAdminSheet<void>(context, (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetHeader(title),
          if (conflicts.isEmpty) Text(t('لم يرسل الخادم تفاصيل.', 'The server sent no details.')),
          for (final x in conflicts) _conflictLine(ctx, x),
        ]),
      ));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: p, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final c = context.colors;
    final d = data;
    final items = d?.items ?? const <ScheduleSuggestion>[];
    final h = ScheduleHealth.from(conflicts: p.conflicts, result: asMap(p.schedule?['result']), suggestions: items);
    final shown = [for (final s in items) if (filter == 'all' || s.status == filter) s];
    final canAct = widget.canEdit && draft;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        if (d?.mock == true)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: RowCard(
                  accent: c.purple,
                  child: Text(t('وضع تجريبي (للتطوير فقط): الاقتراحات مولّدة محلياً، لم يتحقق منها الخادم، و«التطبيق» لا يغيّر الجدول.',
                      'Development mock: suggestions are built locally, not verified by the server, and "apply" does not change the timetable.')))),
        if (!draft)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: RowCard(accent: c.warning, child: Text(t('الجدول منشور — أوقف النشر لتطبيق أي تغيير.', 'The timetable is published — unpublish it to apply changes.')))),
        OrgSectionTitle(t('حالة الجدول', 'Timetable health'), subtitle: h.valid ? t('لا تعارضات إلزامية ولا حصص ناقصة', 'No hard clashes and nothing unplaced') : t('يحتاج تعديلات ليصبح صالحاً', 'Needs changes to be valid')),
        OrgGrid(minTile: 165, children: [
          OrgStatTile(icon: Icons.report_rounded, label: t('تعارضات حالية', 'Open conflicts'), value: h.remaining, color: h.remaining > 0 ? c.danger : c.success),
          OrgStatTile(icon: Icons.task_alt_rounded, label: t('حُلّت بالاقتراحات', 'Resolved by suggestions'), value: h.resolvedByApplied ?? '—', color: c.success),
          OrgStatTile(icon: Icons.summarize_rounded, label: t('الإجمالي', 'Total conflicts'), value: h.total, color: c.primary),
          OrgStatTile(icon: Icons.block_rounded, label: t('قيود إلزامية', 'Hard violations'), value: h.hard, color: h.hard > 0 ? c.danger : c.success),
          OrgStatTile(icon: Icons.warning_amber_rounded, label: t('تحذيرات', 'Warnings'), value: h.warnings, color: c.warning),
          OrgStatTile(icon: Icons.tune_rounded, label: t('تفضيلات غير محققة', 'Soft violations'), value: h.soft, color: c.accent2),
          OrgStatTile(icon: Icons.class_rounded, label: t('محاضرات غير مجدولة', 'Unplaced lectures'), value: h.unscheduledLectures, color: h.unscheduledLectures > 0 ? c.danger : c.success),
          OrgStatTile(icon: Icons.science_rounded, label: t('سكاشن غير مجدولة', 'Unplaced labs'), value: h.unscheduledLabs, color: h.unscheduledLabs > 0 ? c.danger : c.success),
          OrgStatTile(icon: Icons.pending_actions_rounded, label: t('اقتراحات معلقة', 'Pending suggestions'), value: h.suggestions['pending'], color: c.primary, onTap: () => setState(() => filter = 'pending')),
          OrgStatTile(icon: Icons.thumb_up_alt_rounded, label: t('مقبولة / مطبقة', 'Accepted / applied'), value: (h.suggestions['accepted'] ?? 0) + (h.suggestions['applied'] ?? 0), color: c.success, onTap: () => setState(() => filter = 'applied')),
          OrgStatTile(icon: Icons.thumb_down_alt_rounded, label: t('مرفوضة', 'Rejected'), value: h.suggestions['rejected'], color: c.textMedium, onTap: () => setState(() => filter = 'rejected')),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            if (h.resultStatus != null) OrgPill('${t('نتيجة التوليد', 'Generation')}: ${resultStatusLabels()[h.resultStatus] ?? h.resultStatus}', icon: Icons.auto_awesome_rounded),
            if (h.placementRate != null) OrgPill('${t('نسبة الجدولة', 'Placed')}: ${(h.placementRate! * 100).toStringAsFixed(0)}% (${h.sessionsPlaced}/${h.sessionsRequired})', color: h.placementRate == 1 ? c.success : c.warning),
            if (h.softCost != null) OrgPill('${t('تكلفة التفضيلات', 'Soft cost')}: ${h.softCost}', color: c.accent2),
            if (h.resultStatus == null) OrgPill(t('لا يوجد تقرير توليد لهذه النسخة', 'No generation report for this version'), color: c.textMedium),
          ]),
        ),
        if (h.requiredChanges.isNotEmpty) ...[
          OrgSectionTitle(t('المطلوب ليصبح الجدول صالحاً', 'Needed for a valid timetable')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RowCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in h.requiredChanges) Text('• $l', style: orgText(context, size: 12.5))])),
          ),
        ],
        _HorizonCard(p: p, canEdit: widget.canEdit && draft, canForce: widget.canApprove && draft),
        RelaxationCard(p: p, canEdit: widget.canEdit && draft),
        OrgSectionTitle(
          t('الاقتراحات', 'Suggestions'),
          subtitle: t('كل اقتراح يُعاد التحقق منه على أحدث نسخة قبل التطبيق', 'Each one is revalidated on the latest version before it is applied'),
          action: canAct && d?.unsupported != true
              ? TextButton.icon(
                  onPressed: generating ? null : _generate,
                  icon: generating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(t('ابحث عن تحسينات', 'Find improvements')))
              : null,
        ),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Expanded(child: Text(error!, style: orgText(context, color: c.danger))), TextButton(onPressed: _load, child: Text(t('إعادة المحاولة', 'Retry')))])),
        if (d == null && error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (d?.unsupported == true)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RowCard(
                  accent: c.warning,
                  child: Text(t('اقتراحات التحسين تحتاج تحديثاً في الخادم. الأرقام أعلاه حقيقية من التحقق وتقرير التوليد.',
                      'Improvement suggestions need a server update. The numbers above are real, from validation and the generation report.')))),
        if (d != null && !d.unsupported) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final f in ['pending', 'accepted', 'applied', 'rejected', 'invalidated', 'failed', 'all'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                      label: Text(f == 'all' ? t('الكل', 'All') : suggestionStatusLabel(f)), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
                ),
            ]),
          ),
          if (picked.isNotEmpty && canAct)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PrimaryButton(
                label: t('تطبيق ${picked.length} معاً', 'Apply ${picked.length} together'),
                isLoading: picked.any(busy.contains),
                onPressed: () => _apply([for (final s in items) if (picked.contains(s.id)) s]),
              ),
            ),
          if (shown.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                    child: Text(items.isEmpty ? t('لا اقتراحات بعد — اضغط «ابحث عن تحسينات».', 'No suggestions yet — tap "Find improvements".') : t('لا شيء هنا.', 'Nothing here.'),
                        style: orgText(context, color: c.textMedium)))),
          for (final s in shown) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _card(context, s, canAct)),
        ],
      ]),
    );
  }

  Widget _card(BuildContext context, ScheduleSuggestion s, bool canAct) {
    final c = context.colors;
    final stale = s.isStale(version);
    final allowed = s.permission == 'schedule.approve' || s.needsApproval ? widget.canApprove : widget.canEdit;
    final pending = s.status == 'pending';
    final color = switch (s.status) { 'applied' => c.success, 'rejected' => c.textMedium, 'failed' || 'invalidated' => c.danger, _ => c.primary };
    return RowCard(
      accent: s.valid == false ? c.danger : (stale && pending ? c.warning : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (pending && canAct && allowed && s.applicable && !s.expandsConfig)
            Checkbox(value: picked.contains(s.id), onChanged: (v) => setState(() => v == true ? picked.add(s.id) : picked.remove(s.id))),
          Icon(suggestionTypeIcon(s.type), color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, style: orgText(context, w: FontWeight.w800))),
          OrgPill(applying.contains(s.id) ? t('يجري التطبيق…', 'Applying…') : suggestionStatusLabel(s.status), color: color),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          OrgPill(suggestionTypeLabel(s.type), color: c.textMedium),
          if (s.valid == true) OrgPill(t('تحقق منه الخادم', 'Validated'), color: c.success, icon: Icons.verified_rounded),
          if (s.valid == false) OrgPill(t('غير صالح', 'Invalid'), color: c.danger, icon: Icons.error_rounded),
          if (s.valid == null) OrgPill(t('لم يُتحقق منه', 'Not validated'), color: c.warning),
          if (stale && pending) OrgPill(t('الجدول تغيّر منذ الاقتراح', 'Timetable changed since'), color: c.warning, icon: Icons.update_rounded),
          if (!s.applicable) OrgPill(t('نصيحة فقط', 'Advice only'), color: c.textMedium, icon: Icons.lightbulb_outline_rounded),
          if (s.needsApproval) OrgPill(t('يحتاج اعتماد', 'Needs approval'), color: c.purple, icon: Icons.verified_user_rounded),
        ]),
        if (s.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.reason, style: orgText(context, size: 12.5))),
        if (s.affected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [for (final a in s.affected) OrgPill(_affectedLabel(a), color: c.accent2)]),
          ),
        for (final ch in s.changes) Padding(padding: const EdgeInsets.only(top: 6), child: _changeLine(context, ch)),
        for (final l in _configLines(context, s.config)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $l', style: orgText(context, size: 12.5))),
        Padding(padding: const EdgeInsets.only(top: 6), child: _impactLine(context, s.impact)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(suggestionTradeOff(s), style: orgText(context, size: 12, color: c.textMedium))),
        if (s.introducedConflicts.isNotEmpty || s.violations.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(t('ما يسببه هذا التغيير:', 'What this change causes:'), style: orgText(context, size: 12, w: FontWeight.w800, color: c.danger)),
          for (final x in [...s.violations, ...s.introducedConflicts]) _conflictLine(context, x),
        ],
        if (s.decisionReason != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t('السبب', 'Reason')}: ${s.decisionReason}', style: orgText(context, size: 12, color: c.textMedium))),
        if (s.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.error!, style: orgText(context, size: 12, color: c.danger))),
        if (canAct && pending && !allowed)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('يحتاج صلاحية الاعتماد', 'Needs approval rights'), style: orgText(context, size: 12, color: c.textMedium))),
        if (canAct && ((pending && allowed) || (s.status == 'applied' && s.revisionBeforeId != null)))
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(spacing: 8, children: [
              if (pending && allowed) TextButton(onPressed: busy.contains(s.id) ? null : () => _reject(s), child: Text(t('رفض', 'Reject'))),
              if (pending && allowed && s.applicable)
                FilledButton.icon(
                  onPressed: busy.contains(s.id) || s.valid == false ? null : () => _apply([s]),
                  icon: busy.contains(s.id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                  label: Text(stale ? t('تحقق وطبّق', 'Revalidate & apply') : t('قبول وتطبيق', 'Accept & apply')),
                ),
              if (s.status == 'applied' && s.revisionBeforeId != null) TextButton.icon(onPressed: () => _undo(s), icon: const Icon(Icons.undo_rounded), label: Text(t('تراجع', 'Undo'))),
            ]),
          ),
      ]),
    );
  }

  String _affectedLabel(Map<String, dynamic> a) {
    final label = '${a['label'] ?? ''}';
    if (label.isNotEmpty) return label;
    final id = asInt(a['id']);
    return switch (a['type']) {
      'course' => p.loads.where((l) => asInt(l['course_id']) == id).map((l) => '${l['course']?['name_ar'] ?? l['course_name'] ?? '#$id'}').firstOrNull ?? '#$id',
      'room' => _room(id),
      'teacher' || 'assistant' => _person(id),
      _ => '${a['type']} #$id',
    };
  }

  String _room(int? id) => id == null ? '—' : '${p.rooms.where((r) => asInt(r['id']) == id).firstOrNull?['name'] ?? '#$id'}';
  String _person(int? id) => id == null ? '—' : '${p.staff.where((m) => asInt((m['user'] as Map)['id']) == id).map((m) => (m['user'] as Map)['name']).firstOrNull ?? '#$id'}';
  String _period(int? id) => id == null ? '—' : '${p.periods.where((x) => asInt(x['id']) == id).firstOrNull?['label'] ?? '#$id'}';

  String _cell(Map<String, dynamic> m) => [
        if (m['day'] != null) dayLabels()['${m['day']}'] ?? '${m['day']}',
        if (m['period_id'] != null) _period(asInt(m['period_id'])),
        if (m['room_id'] != null) _room(asInt(m['room_id'])),
        if (m['teacher_id'] != null) _person(asInt(m['teacher_id'])),
        if (m['assistant_id'] != null) _person(asInt(m['assistant_id'])),
      ].join(' · ');

  Widget _changeLine(BuildContext context, SuggestionChange ch) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: c.textLight),
        const SizedBox(width: 4),
        Expanded(
            child: Text(
                '${ch.groupNo == null ? '' : '${ch.kind == 'lab' ? t('سكشن', 'Lab') : t('محاضرة', 'Lecture')} G${ch.groupNo} · '}'
                '${ch.before.isEmpty ? '' : _cell(ch.before)}${ch.before.isEmpty || ch.after.isEmpty ? '' : '  →  '}${ch.after.isEmpty ? (ch.op == 'remove' ? t('حذف', 'remove') : '') : _cell(ch.after)}',
                style: orgText(context, size: 12.5, w: FontWeight.w700))),
      ]),
      if (ch.reason.isNotEmpty) Padding(padding: const EdgeInsetsDirectional.only(start: 20), child: Text(ch.reason, style: orgText(context, size: 12, color: c.textMedium))),
    ]);
  }
}

List<String> _configLines(BuildContext context, Map<String, dynamic> config) {
  final out = <String>[];
  final days = asMap(config['days']);
  if (days.isNotEmpty) {
    String names(Object? l) => [for (final d in (l as List? ?? const [])) dayLabels()['$d'] ?? '$d'].join('، ');
    out.add(t('الأيام: ${(days['before'] as List?)?.length ?? '—'} ← ${(days['after'] as List?)?.length ?? '—'} (${names(days['after'])})',
        'Study days: ${(days['before'] as List?)?.length ?? '—'} → ${(days['after'] as List?)?.length ?? '—'} (${names(days['after'])})'));
  }
  final per = asMap(config['periods']);
  if (per['before'] != null || per['after'] != null) out.add(t('الفترات اليومية: ${per['before'] ?? '—'} ← ${per['after'] ?? '—'}', 'Periods per day: ${per['before'] ?? '—'} → ${per['after'] ?? '—'}'));
  for (final x in asMapList(per['add'])) {
    out.add(t('فترة جديدة (لكل جداول المؤسسة): ${x['label'] ?? ''} ${x['start_time'] ?? ''}–${x['end_time'] ?? ''}',
        'New period (shared by every timetable): ${x['label'] ?? ''} ${x['start_time'] ?? ''}–${x['end_time'] ?? ''}'));
  }
  for (final r in asMapList(asMap(config['rooms'])['add'])) {
    out.add(t('مكان جديد: ${r['name'] ?? ''} (${r['kind'] ?? ''}، ${r['capacity'] ?? '?'} مقعد)', 'New room: ${r['name'] ?? ''} (${r['kind'] ?? ''}, ${r['capacity'] ?? '?'} seats)'));
  }
  for (final g in asMapList(config['groups'])) {
    out.add(t('مجموعات المقرر #${g['course_id']}: ${g['before'] ?? '—'} ← ${g['after'] ?? '—'}', 'Course #${g['course_id']} groups: ${g['before'] ?? '—'} → ${g['after'] ?? '—'}'));
  }
  return out;
}

Widget _impactLine(BuildContext context, SuggestionImpact i) {
  final c = context.colors;
  final parts = [
    if (i.resolved != null) t('يحل ${i.resolved}', 'resolves ${i.resolved}'),
    if (i.introduced != null) t('يُحدث ${i.introduced}', 'introduces ${i.introduced}'),
    if (i.remaining != null) t('يتبقى ${i.remaining}', '${i.remaining} remain'),
    if (i.unscheduledBefore != null) t('غير مجدول: ${i.unscheduledBefore} ← ${i.unscheduledAfter ?? '?'}', 'unplaced: ${i.unscheduledBefore} → ${i.unscheduledAfter ?? '?'}'),
    if (i.softCostBefore != null && i.softCostAfter != null) t('تكلفة التفضيلات: ${i.softCostBefore} ← ${i.softCostAfter}', 'soft cost: ${i.softCostBefore} → ${i.softCostAfter}'),
  ];
  return Text(parts.isEmpty ? t('لم يرسل الخادم أثراً متوقعاً', 'No expected impact from the server') : parts.join(' · '),
      style: orgText(context, size: 12, w: FontWeight.w700, color: (i.introduced ?? 0) > 0 ? c.danger : c.textMedium));
}

Widget _conflictLine(BuildContext context, Map<String, dynamic> x) {
  final c = context.colors;
  final what = _bi(x, 'text');
  final where = [
    if (x['day'] != null) dayLabels()['${x['day']}'] ?? '${x['day']}',
    for (final tm in asMapList(x['times'])) '${tm['label'] ?? ''}',
    ...((x['courses'] as List?) ?? const []).map((e) => '$e'),
  ].where((e) => e.isNotEmpty).join(' · ');
  return Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text('• ${what.isEmpty ? '${x['type']}' : what}${where.isEmpty ? '' : ' — $where'}',
        style: orgText(context, size: 12, color: x['severity'] == 'error' ? c.danger : c.textMedium)),
  );
}

/// Days / periods policy and, in forced mode, the days themselves. Saved in settings.horizon with PUT /schedules/{sid}.
class _HorizonCard extends StatelessWidget {
  const _HorizonCard({required this.p, required this.canEdit, required this.canForce});
  final OrgScheduleProvider p;
  final bool canEdit, canForce;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sch = p.schedule ?? const {};
    final settings = asMap(sch['settings']);
    final h = ScheduleHorizon.fromSettings(settings);
    final days = ScheduleDraft.fromJson(sch).days;
    final problem = h.check(days.length, p.periods.length);
    return Column(children: [
      OrgSectionTitle(t('الأيام والفترات', 'Days and periods'),
          action: canEdit ? TextButton.icon(onPressed: () => _edit(context, h, days), icon: const Icon(Icons.edit_rounded), label: Text(t('تعديل', 'Edit'))) : null),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: RowCard(
          accent: problem != null ? c.warning : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              OrgPill(h.mode == 'forced' ? t('إعداد مفروض', 'Forced configuration') : t('مرن — الاقتراحات تحتاج موافقة', 'Flexible — proposals need approval'), color: c.primary),
              OrgPill(t('${days.length} أيام', '${days.length} days')),
              OrgPill(t('${p.periods.length} فترات يومياً', '${p.periods.length} periods / day')),
              OrgPill(t('الأيام ${h.minDays}–${h.maxDays}', 'Days ${h.minDays}–${h.maxDays}'), color: c.textMedium),
              if (h.maxPeriods != null) OrgPill(t('حتى ${h.maxPeriods} فترات', 'Up to ${h.maxPeriods} periods'), color: c.textMedium),
              OrgPill(h.allowExpansion ? t('يمكن اقتراح توسيع', 'May propose expansion') : t('بلا اقتراحات توسيع', 'No expansion proposals'), color: c.textMedium),
              if (h.autoApplyApproved) OrgPill(t('تطبيق تلقائي بعد الاعتماد', 'Auto-apply once approved'), color: c.purple),
            ]),
            const SizedBox(height: 6),
            Text(dayNames(days), style: orgText(context, size: 12, color: c.textMedium)),
            if (problem != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem, style: orgText(context, size: 12, color: c.warning))),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('الفترات مشتركة بين كل جداول المؤسسة وتُدار من تبويب الفترات.', 'Periods are shared by every timetable of the organization and managed in the Periods tab.'),
                  style: orgText(context, size: 11.5, color: c.textLight)),
            ),
          ]),
        ),
      ),
    ]);
  }

  static String dayNames(List<String> days) => [for (final d in days) dayLabels()[d] ?? d].join('، ');

  Future<void> _edit(BuildContext context, ScheduleHorizon start, List<String> startDays) async {
    var h = start;
    final days = startDays.toSet();
    bool busy = false;
    String? err;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final forced = h.mode == 'forced';
          final problem = h.check(days.length, p.periods.length);
          Widget stepper(String label, int v, int min, int max, ValueChanged<int> on) => Row(children: [
                Expanded(child: Text('$label: $v', style: orgText(ctx, w: FontWeight.w700))),
                IconButton(onPressed: v > min ? () => set(() => on(v - 1)) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                IconButton(onPressed: v < max ? () => set(() => on(v + 1)) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
              ]);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('الأيام والفترات', 'Days and periods')),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'flexible', label: Text(t('مرن', 'Flexible'))),
                  ButtonSegment(value: 'forced', label: Text(t('مفروض', 'Forced')), enabled: canForce),
                ],
                selected: {h.mode},
                onSelectionChanged: (v) => set(() => h = h.copyWith(mode: v.first)),
              ),
              const SizedBox(height: 6),
              Text(
                  forced
                      ? t('تحدد الأيام بنفسك. القيود الإلزامية (الطلاب، المدرسون، الأماكن، السعة) تبقى مطبقة وسيُعاد التحقق من الجدول.',
                          'You set the days yourself. Hard rules (students, staff, rooms, capacity) still apply and the timetable is revalidated.')
                      : t('يمكن للنظام اقتراح أيام أو فترات إضافية ضمن الحدود، ولا يُطبّق شيء دون موافقة.', 'The system may propose extra days or periods within the limits; nothing applies without approval.'),
                  style: orgText(ctx, size: 12, color: c.textMedium)),
              const SizedBox(height: 10),
              if (forced) ...[
                Text(t('أيام الدراسة', 'Study days'), style: orgText(ctx, w: FontWeight.w800)),
                Wrap(spacing: 6, children: [
                  for (final d in scheduleDays)
                    FilterChip(label: Text(dayLabels()[d] ?? d), selected: days.contains(d), onSelected: (v) => set(() => v ? days.add(d) : (days.length > 1 ? days.remove(d) : null))),
                ]),
                const SizedBox(height: 8),
              ],
              stepper(t('أقل عدد أيام', 'Minimum days'), h.minDays, 1, 7, (v) => h = h.copyWith(minDays: v)),
              stepper(t('أقصى عدد أيام', 'Maximum days'), h.maxDays, 1, 7, (v) => h = h.copyWith(maxDays: v)),
              Row(children: [
                Expanded(child: Text('${t('أقصى فترات يومياً', 'Max periods per day')}: ${h.maxPeriods ?? t('بلا حد', 'no limit')}', style: orgText(ctx, w: FontWeight.w700))),
                IconButton(
                    onPressed: (h.maxPeriods ?? p.periods.length) > 1 ? () => set(() => h = h.copyWith(maxPeriods: () => (h.maxPeriods ?? p.periods.length) - 1)) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded)),
                IconButton(
                    onPressed: (h.maxPeriods ?? p.periods.length) < 16 ? () => set(() => h = h.copyWith(maxPeriods: () => (h.maxPeriods ?? p.periods.length) + 1)) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded)),
                if (h.maxPeriods != null) TextButton(onPressed: () => set(() => h = h.copyWith(maxPeriods: () => null)), child: Text(t('بلا حد', 'No limit'))),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: h.allowExpansion,
                title: Text(t('السماح باقتراح أيام / فترات إضافية', 'Allow proposals for extra days / periods')),
                onChanged: (v) => set(() => h = h.copyWith(allowExpansion: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: h.autoApplyApproved,
                title: Text(t('تطبيق التوسيع فور اعتماده', 'Apply an expansion as soon as it is approved')),
                onChanged: canForce ? (v) => set(() => h = h.copyWith(autoApplyApproved: v)) : null,
              ),
              if (forced && (days.length != startDays.length || !days.containsAll(startDays)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(t('قبل: ${dayNames(startDays)}\nبعد: ${dayNames([for (final d in scheduleDays) if (days.contains(d)) d])}',
                      'Before: ${dayNames(startDays)}\nAfter: ${dayNames([for (final d in scheduleDays) if (days.contains(d)) d])}'),
                      style: orgText(ctx, size: 12.5, w: FontWeight.w700)),
                ),
              if (problem != null) Text(problem, style: orgText(ctx, size: 12, color: c.danger)),
              if (err != null) Text(err!, style: orgText(ctx, size: 12, color: c.danger)),
              const SizedBox(height: 8),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ وإعادة التحقق', 'Save and revalidate'),
                onPressed: problem != null
                    ? null
                    : () async {
                        set(() {
                          busy = true;
                          err = null;
                        });
                        final d = ScheduleDraft.fromJson(p.schedule!, allCourses: [for (final l in p.loads) asInt(l['course_id'])]);
                        d.settings['horizon'] = h.toJson();
                        if (forced) d.days = days.toList();
                        final r = await p.saveDraft(d);
                        if (!r.ok) {
                          set(() {
                            busy = false;
                            err = orgErrorText(r.error!);
                          });
                          return;
                        }
                        await p.open(asInt(p.schedule!['id']));
                        if (ctx.mounted) Navigator.pop(ctx);
                        toast(t('حُفظ — أُعيد التحقق من الجدول', 'Saved — the timetable was revalidated'));
                      },
              ),
            ]),
          );
        }));
  }
}

/// The order relaxable restrictions give way in (settings.relaxation_priority). Hard rules are not in the list:
/// they never relax. The server's solver today tells only assistants from teachers (settings.relax_order =
/// role_then_experience); the full order ranks alternatives here and is stored for the server
/// (docs/backend/scheduling-spec.md G1).
class RelaxationCard extends StatelessWidget {
  const RelaxationCard({super.key, required this.p, required this.canEdit});
  final OrgScheduleProvider p;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = asMap(p.schedule?['settings']);
    final policy = RelaxationPolicy.fromSettings(settings);
    return Column(children: [
      OrgSectionTitle(t('أولوية التخفيف', 'Relaxation priority'),
          subtitle: t('عند التعذر يُخفَّف الأعلى أولاً — والقيود الإلزامية لا تُخفَّف أبداً', 'When needed, the top one gives way first — hard rules never do'),
          action: canEdit ? TextButton.icon(onPressed: () => _edit(context, policy), icon: const Icon(Icons.swap_vert_rounded), label: Text(t('ترتيب', 'Reorder'))) : null),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: RowCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < policy.order.length; i++) Text('${i + 1}. ${relaxTierLabel(policy.order[i])}', style: orgText(context, size: 12.5, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                settings['relax_order'] == 'role_then_experience'
                    ? t('الخادم يطبّق حالياً: تفضيلات المعيدين قبل المدرسين (ثم الأقل خبرة). باقي الترتيب يُستخدم لترتيب البدائل.',
                        'The server applies today: assistants\' preferences before teachers\' (then less experience). The rest of the order ranks the alternatives.')
                    : t('الخادم لا يفرّق حالياً بين الأدوار عند التخفيف. الترتيب يُستخدم لترتيب البدائل.', 'The server does not tell roles apart when relaxing today. The order ranks the alternatives.'),
                style: orgText(context, size: 11.5, color: c.textLight)),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, RelaxationPolicy start) async {
    var policy = start;
    var busy = false;
    String? err;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('أولوية التخفيف', 'Relaxation priority')),
              Text(t('الأول يُخفَّف أولاً. لا يدخل هنا: أهلية المدرس، سعة المكان، التجهيزات، عدم التداخل، الصلاحيات.',
                  'The first gives way first. Never in this list: staff eligibility, room capacity, facilities, no double booking, permissions.'),
                  style: orgText(ctx, size: 12, color: c.textMedium)),
              const SizedBox(height: 8),
              for (var i = 0; i < policy.order.length; i++)
                Row(children: [
                  Expanded(child: Text('${i + 1}. ${relaxTierLabel(policy.order[i])}', style: orgText(ctx, w: FontWeight.w700))),
                  IconButton(onPressed: i == 0 ? null : () => set(() => policy = policy.move(policy.order[i], -1)), icon: const Icon(Icons.arrow_upward_rounded)),
                  IconButton(onPressed: i == policy.order.length - 1 ? null : () => set(() => policy = policy.move(policy.order[i], 1)), icon: const Icon(Icons.arrow_downward_rounded)),
                ]),
              if (policy.rank('teacher_prefs') != policy.order.length - 1)
                Text(t('تنبيه: تفضيلات المدرسين لم تعد الأخيرة.', 'Note: teacher preferences are no longer last.'), style: orgText(ctx, size: 12, color: c.warning)),
              if (err != null) Text(err!, style: orgText(ctx, size: 12, color: c.danger)),
              const SizedBox(height: 8),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ', 'Save'),
                onPressed: () async {
                  set(() {
                    busy = true;
                    err = null;
                  });
                  final d = ScheduleDraft.fromJson(p.schedule!, allCourses: [for (final l in p.loads) asInt(l['course_id'])]);
                  d.settings['relaxation_priority'] = policy.toJson();
                  // the part the server's solver understands today
                  d.settings['relax_order'] = policy.rank('assistant_prefs') < policy.rank('teacher_prefs') ? 'role_then_experience' : 'none';
                  final r = await p.saveDraft(d);
                  if (!r.ok) {
                    set(() {
                      busy = false;
                      err = orgErrorText(r.error!);
                    });
                    return;
                  }
                  await p.open(asInt(p.schedule!['id']));
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast(t('حُفظ — يُطبّق في التوليد القادم', 'Saved — used by the next generation'));
                },
              ),
            ]),
          );
        }));
  }
}
