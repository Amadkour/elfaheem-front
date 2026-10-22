// lib/features/org/org_schedule_coverage.dart — "generate until every session is placed".
//
// A loop the creator drives: generate → see what is still unplaced and why → pick an option → the server applies it
// → next round. It ends only when every required session is placed or the creator says "Enough".
//
//   UnplacedSession / CoverageState  pure: what the last generation could not place, from schedule.result
//   coverageLadder                   pure: the order options are offered in. Two rules are NEVER broken — a room
//                                    holding two sessions at once and a member teaching two sessions at once — so
//                                    for those the ladder is: rearrange the conflicting timetables → add a member →
//                                    add a time (day / period) → add a room. Every other rule may be broken, in the
//                                    relaxation priority order (settings.relaxation_priority).
//   RebalanceApi                     applying a change to EVERY timetable of the term, with one rollback — Remote
//                                    (POST …/schedules/rebalance, docs/backend/scheduling-spec.md) · Mock (dev only)
//
// Rollback: a manual revision is saved before the first round; every applied option records the server's
// revision_before_id. Restoring either is POST …/revisions/{id}/restore. Nothing here is estimated: the counts are
// the server's (generation report, suggestion impact).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_providers.dart';
import 'org_schedule_copies.dart' show timetableNamesOf;
import 'org_schedule_optimizer.dart';
import 'org_schedule_planning.dart' show kOrgSchedulingMocks;
import 'org_schedule_versions.dart';
import 'org_ui.dart';
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

/// Solver reasons that mean a double booking would be needed — never relaxed.
const untouchableReasons = {'rooms_busy', 'teacher_busy'};

/// What the creator can do about an unplaced session, cheapest first.
const coverageSteps = ['break_by_priority', 'rearrange_all', 'add_member', 'add_time', 'add_room'];

class UnplacedSession {
  const UnplacedSession({required this.courseId, required this.kind, this.groupNo, required this.missing, required this.reason, this.blocking = const {}, this.teacherId});
  final int courseId, missing;
  final int? groupNo, teacherId;
  final String kind, reason;
  final Map<String, int> blocking; // reason → how many candidate times it blocked

  bool get untouchable => untouchableReasons.contains(reason);

  factory UnplacedSession.fromJson(Map<String, dynamic> j) => UnplacedSession(
        courseId: asInt(j['course_id']),
        kind: '${j['kind'] ?? 'lecture'}',
        groupNo: j['group_no'] == null ? null : asInt(j['group_no']),
        missing: asInt(j['missing'], 1),
        reason: '${j['reason'] ?? j['type'] ?? 'no_free_cell'}',
        blocking: {for (final e in asMap(j['blocking']).entries) e.key: asInt(e.value)},
        teacherId: j['teacher_id'] == null ? null : asInt(j['teacher_id']),
      );
}

class CoverageState {
  const CoverageState({required this.unplaced, this.required, this.placed, this.rulesBroken = false, this.status, this.brokenByTier = const {}});
  final List<UnplacedSession> unplaced;
  final int? required, placed; // the generation report's stats; null when it sent none
  final bool rulesBroken; // the server reported it broke rules by priority (result.relaxation_mode echoed)
  final String? status;
  final Map<String, int> brokenByTier; // result.broken_by_tier: rules broken on purpose, per relaxation tier

  int get broken => brokenByTier.values.fold(0, (a, n) => a + n);

  int get missing => unplaced.fold(0, (a, u) => a + u.missing);
  bool get covered => missing == 0 && (required == null || placed == null || placed! >= required!);
  double? get rate => required == null || placed == null || required == 0 ? null : placed! / required!;

  factory CoverageState.of(Map<String, dynamic> result) {
    final stats = asMap(result['stats']);
    return CoverageState(
      unplaced: asMapList(result['unscheduled']).map(UnplacedSession.fromJson).toList(),
      required: stats['sessions_required'] == null ? null : asInt(stats['sessions_required']),
      placed: stats['sessions_placed'] == null ? null : asInt(stats['sessions_placed']),
      rulesBroken: result['relaxation_mode'] == relaxationModeAllButDoubleBooking,
      status: result['status'] as String?,
      brokenByTier: {for (final e in asMap(result['broken_by_tier']).entries) e.key: asInt(e.value)},
    );
  }
}

/// Sent with generate (this run only); docs/backend/scheduling-spec.md — the server echoes it in result when applied.
const relaxationModeAllButDoubleBooking = 'all_but_double_booking';

/// The options for one unplaced session, in the order they are offered.
List<String> coverageLadder(UnplacedSession u) => switch (u.reason) {
      'rooms_busy' || 'teacher_busy' => const ['rearrange_all', 'add_member', 'add_time', 'add_room'],
      'teacher_unavailable' || 'teacher_day_limit' => const ['break_by_priority', 'add_member', 'add_time'],
      'students_clash' || 'students_busy_elsewhere' || 'students_unavailable' => const ['break_by_priority', 'rearrange_all', 'add_time'],
      'no_room_fits' => const ['break_by_priority', 'add_room'],
      _ => const ['add_time', 'add_room'],
    };

/// Which server suggestion types carry out a step.
const stepSuggestionTypes = {
  'rearrange_all': {'reschedule_session', 'combined'},
  'add_member': {'reassign_staff', 'add_staff'},
  'add_time': {'add_period', 'add_day'},
  'add_room': {'add_room'},
};

String coverageStepOf(String suggestionType) =>
    stepSuggestionTypes.entries.firstWhere((e) => e.value.contains(suggestionType), orElse: () => const MapEntry('rearrange_all', {})).key;

/// Server suggestions worth showing in the loop — pending, not known to break a hard rule — ordered by the ladder
/// step, then by how many sessions they place.
List<ScheduleSuggestion> coverageOptions(List<ScheduleSuggestion> items) {
  final out = items.where((s) => s.status == 'pending' && s.valid != false && s.applicable).toList();
  int placed(ScheduleSuggestion s) => (s.impact.unscheduledBefore ?? 0) - (s.impact.unscheduledAfter ?? s.impact.unscheduledBefore ?? 0);
  out.sort((a, b) {
    final st = coverageSteps.indexOf(coverageStepOf(a.type)).compareTo(coverageSteps.indexOf(coverageStepOf(b.type)));
    return st != 0 ? st : placed(b).compareTo(placed(a));
  });
  return out;
}

/// Advice the server measured but cannot apply (hire a member, open a room), in ladder order — shown, never accepted.
List<ScheduleSuggestion> coverageAdvice(List<ScheduleSuggestion> items) =>
    items.where((s) => s.status == 'pending' && !s.applicable).toList()
      ..sort((a, b) => coverageSteps.indexOf(coverageStepOf(a.type)).compareTo(coverageSteps.indexOf(coverageStepOf(b.type))));

/// "Sunday P1, P2 · Monday P3" — when an add_staff advice needs the new member (config.staff.windows).
String staffWindowsText(Map<String, dynamic> config, List<Map<String, dynamic>> periods) {
  final days = dayLabelsPlain();
  final label = {for (final p in periods) asInt(p['id']): '${p['label'] ?? p['id']}'};
  return asMapList(asMap(config['staff'])['windows'])
      .map((w) => '${days[w['day']] ?? w['day']} ${(w['period_ids'] as List? ?? const []).map((id) => label[asInt(id)] ?? '#$id').join('، ')}')
      .join(' · ');
}

String coverageStepLabel(String s) => switch (s) {
      'break_by_priority' => t('كسر القيد حسب الأولوية', 'Break the rule by priority'),
      'rearrange_all' => t('إعادة ترتيب الجداول المتعارضة', 'Rearrange the conflicting timetables'),
      'add_member' => t('إضافة عضو (مدرس / معيد آخر)', 'Add a member (another teacher / assistant)'),
      'add_time' => t('إضافة موعد (يوم / فترة)', 'Add a time (day / period)'),
      _ => t('إضافة مكان', 'Add a room'),
    };

String unplacedReasonText(String r) => switch (r) {
      'rooms_busy' => t('كل الأماكن المناسبة محجوزة في كل وقت ممكن — لا يُسمح بحصتين في المكان نفسه', 'Every fitting room is taken at every possible time — two sessions never share a room'),
      'teacher_busy' => t('المدرس يدرّس مقرراً آخر في كل وقت ممكن — لا يُسمح بالتداخل', 'The teacher teaches another course at every possible time — never double-booked'),
      'teacher_unavailable' => t('المدرس غير متاح في الأوقات المناسبة', 'The teacher is unavailable at the fitting times'),
      'teacher_day_limit' => t('تجاوز الحد اليومي للمدرس', 'Over the teacher\'s daily limit'),
      'students_clash' => t('تتعارض مع مقرر يشترك معه الطلاب', 'Clashes with a course sharing its students'),
      'students_busy_elsewhere' => t('الطلاب مشغولون في جدول منشور آخر', 'The students are busy in another published timetable'),
      'students_unavailable' => t('الطلاب غير متاحين في الأوقات المناسبة', 'The students are unavailable at the fitting times'),
      'no_room_fits' => t('لا مكان بالنوع والسعة والتجهيزات المطلوبة', 'No room has the required kind, capacity and equipment'),
      'course_already_there' => t('لا توجد أوقات كافية لعدد الحصص', 'Not enough distinct times for the number of sessions'),
      'no_consecutive_periods' => t('الحصة تحتاج فترات متتالية أكثر مما في اليوم', 'Needs more consecutive periods than a day has'),
      'removed_by_hand' => t('حُذفت من الجدول يدوياً', 'Removed from the timetable by hand'),
      _ => t('لا يوجد وقت متاح', 'No free time'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Every timetable of the term (server)
// ═════════════════════════════════════════════════════════════════════════════

/// One change applied across timetables: each item can be rolled back to its revision_before_id, all together.
class Changeset {
  const Changeset({required this.id, required this.status, this.items = const [], this.mock = false});
  final String id, status; // running · applied · failed · rolled_back
  final List<Map<String, dynamic>> items; // [{schedule_id, schedule_name, revision_before_id, version_before, version_after, unscheduled_before, unscheduled_after}]
  final bool mock;

  factory Changeset.fromJson(Map<String, dynamic> j, {bool mock = false}) =>
      Changeset(id: '${j['id']}', status: '${j['status'] ?? 'applied'}', items: asMapList(j['items']), mock: mock);
}

abstract class RebalanceApi {
  /// Re-optimizes every draft timetable of [termId] together (or [scheduleIds]), after applying [suggestionId] to the
  /// origin timetable. Throws [ApiException]; a missing route is told apart by [orgEndpointMissing].
  Future<Changeset> rebalance({required int originId, int? termId, String? suggestionId, required Map<int, int?> versions});
  Future<Changeset> get(String id);
  Future<Changeset> rollback(String id);
}

class RemoteRebalanceApi implements RebalanceApi {
  RemoteRebalanceApi(this.api, this.base);
  final ApiClient api;
  final String base;

  Map<String, dynamic> _cs(dynamic r) => asMap(asMap(r)['changeset']).isEmpty ? asMap(r) : asMap(asMap(r)['changeset']);

  @override
  Future<Changeset> rebalance({required int originId, int? termId, String? suggestionId, required Map<int, int?> versions}) async =>
      Changeset.fromJson(_cs(await api.post('$base/schedules/rebalance', body: {
        'origin_schedule_id': originId,
        'term_id': ?termId,
        'suggestion_id': ?suggestionId,
        'expected_versions': {for (final e in versions.entries) '${e.key}': e.value},
      })));

  @override
  Future<Changeset> get(String id) async => Changeset.fromJson(_cs(await api.get('$base/schedules/changesets/$id')));

  @override
  Future<Changeset> rollback(String id) async => Changeset.fromJson(_cs(await api.post('$base/schedules/changesets/$id/rollback')));
}

/// Development only (ORG_SCHEDULING_MOCKS): records the request and answers with this timetable alone.
class MockRebalanceApi implements RebalanceApi {
  final _store = <String, Changeset>{};

  @override
  Future<Changeset> rebalance({required int originId, int? termId, String? suggestionId, required Map<int, int?> versions}) async {
    final id = 'mock-${_store.length + 1}';
    return _store[id] = Changeset(id: id, status: 'applied', mock: true, items: [
      {'schedule_id': originId, 'version_before': versions[originId], 'version_after': (versions[originId] ?? 0) + 1}
    ]);
  }

  @override
  Future<Changeset> get(String id) async => _store[id] ?? (throw ApiException(statusCode: 404, message: 'changeset_not_found'));

  @override
  Future<Changeset> rollback(String id) async => _store[id] = Changeset(id: id, status: 'rolled_back', items: (await get(id)).items, mock: true);
}

MockRebalanceApi? _mockRebalance;
RebalanceApi rebalanceApi(OrgScheduleProvider p) => kOrgSchedulingMocks ? (_mockRebalance ??= MockRebalanceApi()) : RemoteRebalanceApi(p.api, p.base);

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

Future<void> openCoverageRun(BuildContext context, OrgScheduleProvider p, {bool canApprove = false}) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => BasePage(
          useWebCard: true,
          maxWith: 1000,
          appBar: ScreenAppBar(title: t('توليد حتى اكتمال الجدول', 'Generate until complete')),
          child: _CoveragePage(p: p, api: suggestionApi(p), rebalance: rebalanceApi(p), canApprove: canApprove),
        )));

class _Step {
  _Step(this.label, {this.revisionBeforeId, this.changeset, this.allTimetables = false});
  final String label;
  final int? revisionBeforeId;
  Changeset? changeset;
  final bool allTimetables;
  bool rolledBack = false;
}

class _CoveragePage extends StatefulWidget {
  const _CoveragePage({required this.p, required this.api, required this.rebalance, required this.canApprove});
  final OrgScheduleProvider p;
  final SuggestionApi api;
  final RebalanceApi rebalance;
  final bool canApprove;

  @override
  State<_CoveragePage> createState() => _CoveragePageState();
}

class _CoveragePageState extends State<_CoveragePage> {
  bool generating = false, loadingOptions = false, breakRules = true, enough = false;
  String? busyId;
  int round = 0, seed = 7;
  SuggestionList? options;
  int? remainingAfterApply; // the server's unscheduled count after the last applied option (suggestion impact)
  final steps = <_Step>[];

  OrgScheduleProvider get p => widget.p;
  int get sid => asInt(p.schedule?['id']);
  int? get version => p.schedule?['version'] == null ? null : asInt(p.schedule!['version']);
  bool get draft => p.schedule?['status'] != 'active';
  CoverageState get state => CoverageState.of(asMap(p.schedule?['result']));
  bool get hasResult => asMap(p.schedule?['result']).isNotEmpty;

  /// The server's latest word on how many sessions are still missing.
  int? get remaining {
    final fresh = options?.items.where((s) => s.status == 'pending' && s.baseVersion == version && s.impact.unscheduledBefore != null).firstOrNull;
    return fresh?.impact.unscheduledBefore ?? remainingAfterApply ?? (hasResult ? state.missing : null);
  }

  bool get covered => hasResult && remaining == 0;

  @override
  void initState() {
    super.initState();
    if (hasResult && !state.covered) _loadOptions();
  }

  Future<void> _waitForRun() async {
    if (!runIsOpen(p.genRun)) return;
    final done = Completer<void>();
    void check() {
      if (!runIsOpen(p.genRun) && !done.isCompleted) done.complete();
    }

    p.addListener(check);
    await done.future.timeout(const Duration(minutes: 10), onTimeout: () {});
    p.removeListener(check);
    await p.open(sid); // slots + result as stored by the server
  }

  Future<void> _generate() async {
    if (generating) return;
    setState(() => generating = true);
    if (steps.isEmpty) {
      // the start point: everything below can be rolled back to it
      final snap = await p.saveSnapshot(t('قبل التوليد حتى الاكتمال', 'Before generate-until-complete'));
      final rev = asMap(snap.map['revision']).isNotEmpty ? asMap(snap.map['revision']) : snap.map;
      if (snap.ok && rev['id'] != null) steps.add(_Step(t('نقطة البداية', 'Start point'), revisionBeforeId: asInt(rev['id'])));
    }
    final r = await p.startGeneration(
      settings: breakRules ? {'relaxation_mode': relaxationModeAllButDoubleBooking} : null,
      persistSettings: false,
      seed: seed,
    );
    if (r.ok || r.code == 'generation_running') {
      await _waitForRun();
      round++;
      seed++;
      remainingAfterApply = null;
      options = null;
      if (mounted && !state.covered) await _loadOptions();
    } else {
      toast(orgErrorText(r.error!), error: true);
    }
    if (mounted) setState(() => generating = false);
  }

  Future<void> _loadOptions() async {
    setState(() => loadingOptions = true);
    try {
      final r = await widget.api.generate(sid, version: version);
      if (mounted) setState(() => options = r);
    } catch (e) {
      final x = ApiException.from(e);
      if (!orgEndpointMissing(x)) toast(orgErrorText(x), error: true);
    }
    if (mounted) setState(() => loadingOptions = false);
  }

  /// "Only this timetable" or "every timetable of the term" — asked before every applied option.
  Future<String?> _askScope(ScheduleSuggestion s) => showAdminSheet<String>(context, (ctx) {
        final c = ctx.colors;
        Widget choice(String v, IconData icon, String title, String body) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowCard(
                onTap: () => Navigator.pop(ctx, v),
                child: Row(children: [
                  Icon(icon, color: c.primary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: orgText(ctx, w: FontWeight.w800)),
                    Text(body, style: orgText(ctx, size: 12, color: c.textMedium)),
                  ])),
                ]),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('أين يُطبَّق هذا التغيير؟', 'Where should this change apply?')),
            Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, style: orgText(ctx, w: FontWeight.w700)),
            const SizedBox(height: 12),
            choice('this', Icons.table_chart_rounded, t('هذا الجدول فقط', 'This timetable only'),
                t('يُطبَّق هنا وتُحفظ نسخة قبل التغيير للتراجع.', 'Applied here; a version is saved first so it can be rolled back.')),
            choice('all', Icons.account_tree_rounded, t('تحسين كل جداول الفصل', 'Improve every timetable of the term'),
                t('يعيد ترتيب كل الجداول المسودة معاً لتحقيق أكبر عدد من القيود، مع تراجع واحد للكل.', 'Rearranges every draft timetable together to meet the most rules, with one rollback for all.')),
          ]),
        );
      });

  Future<void> _apply(ScheduleSuggestion s) async {
    if (busyId != null) return;
    final scope = await _askScope(s);
    if (scope == null || !mounted) return;
    setState(() => busyId = s.id);
    try {
      if (scope == 'all') {
        await _applyEverywhere(s);
      } else {
        await _applyHere(s);
      }
    } catch (e) {
      final x = ApiException.from(e);
      toast(orgErrorText(x), error: true);
      if (const {'stale_version', 'suggestion_stale', 'suggestion_invalid', 'suggestion_already_applied'}.contains(x.code)) {
        await p.open(sid);
        await _loadOptions();
      }
    }
    if (mounted) setState(() => busyId = null);
  }

  Future<void> _applyHere(ScheduleSuggestion s) async {
    final r = await widget.api.accept(sid, s.id, version: version);
    if (r.run != null) {
      p.genRun = r.run;
      await _followRun(asInt(r.run!['id']));
      remainingAfterApply = null; // the regeneration wrote a fresh report
    } else {
      remainingAfterApply = s.impact.unscheduledAfter;
      await p.open(sid);
    }
    final list = await widget.api.list(sid);
    final now = list.items.where((x) => x.id == s.id).firstOrNull;
    if (now != null && (now.status == 'failed' || now.status == 'invalidated')) {
      remainingAfterApply = null;
      toast(t('تعذّر التطبيق — لم يتغير شيء', 'Could not be applied — nothing changed'), error: true);
    } else {
      steps.add(_Step(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, revisionBeforeId: now?.revisionBeforeId));
      toast(t('طُبّق على الجدول', 'Applied to the timetable'));
    }
    await _loadOptions();
  }

  Future<void> _followRun(int rid) async {
    for (var i = 0; i < 300 && mounted; i++) {
      final g = await orgCall(() => p.api.get('${p.base}/schedules/$sid/runs/$rid'), quiet: true);
      if (g.ok && !runIsOpen(g.map)) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    await p.open(sid);
  }

  Future<void> _applyEverywhere(ScheduleSuggestion s) async {
    try {
      final cs = await widget.rebalance.rebalance(originId: sid, termId: p.schedule?['term_id'] == null ? null : asInt(p.schedule!['term_id']), suggestionId: s.id, versions: {sid: version});
      steps.add(_Step(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, changeset: cs, allTimetables: true));
      await p.open(sid);
      await _loadOptions();
      toast(cs.mock ? t('تجريبي: لم يُرسل شيء للخادم', 'Mock: nothing was sent to the server') : t('طُبّق على جداول الفصل', 'Applied to the term\'s timetables'));
    } catch (e) {
      final x = ApiException.from(e);
      if (!orgEndpointMissing(x)) rethrow;
      if (!mounted) return;
      final here = await confirm(context,
          message: t('الخادم لا يدعم تحسين كل جداول الفصل معاً بعد. هل تريد تطبيق التغيير على هذا الجدول فقط؟',
              'The server cannot improve every timetable of the term together yet. Apply the change to this timetable only?'));
      if (here) await _applyHere(s);
    }
  }

  /// Rearrange every draft timetable of the term together (no suggestion): for sessions that only a double booking
  /// could place here, another timetable's sessions may move instead.
  Future<void> _rebalanceAll() async {
    if (busyId != null) return;
    setState(() => busyId = 'rebalance');
    try {
      final cs = await widget.rebalance.rebalance(originId: sid, termId: asInt(p.schedule!['term_id']), versions: {sid: version});
      steps.add(_Step(coverageStepLabel('rearrange_all'), changeset: cs, allTimetables: true));
      remainingAfterApply = null;
      await p.open(sid);
      await _loadOptions();
      toast(cs.mock ? t('تجريبي: لم يُرسل شيء للخادم', 'Mock: nothing was sent to the server') : t('أُعيد ترتيب جداول الفصل', 'The term\'s timetables were rearranged'));
    } catch (e) {
      final x = ApiException.from(e);
      toast(orgEndpointMissing(x) ? t('الخادم لا يدعم تحسين كل جداول الفصل معاً بعد', 'The server cannot rearrange every timetable of the term yet') : orgErrorText(x), error: true);
      if (x.code == 'stale_version') await p.open(sid);
    }
    if (mounted) setState(() => busyId = null);
  }

  Future<void> _reject(ScheduleSuggestion s) async {
    try {
      await widget.api.reject(sid, s.id);
      await _loadOptions();
    } catch (e) {
      toast(orgErrorText(ApiException.from(e)), error: true);
    }
  }

  Future<void> _rollback(_Step st) async {
    if (!await confirm(context,
        message: st.allTimetables
            ? t('التراجع عن هذا التغيير في كل الجداول التي شملها؟', 'Roll this change back in every timetable it touched?')
            : t('استرجاع الجدول كما كان قبل هذه الخطوة؟ تُحفظ نسخة جديدة ولا يُحذف شيء.', 'Restore the timetable as it was before this step? A new version is saved; nothing is deleted.'))) {
      return;
    }
    if (st.changeset != null) {
      try {
        st.changeset = await widget.rebalance.rollback(st.changeset!.id);
        st.rolledBack = st.changeset!.status == 'rolled_back';
        await p.open(sid);
      } catch (e) {
        toast(orgErrorText(ApiException.from(e)), error: true);
      }
    } else if (await p.restoreRevision(st.revisionBeforeId!)) {
      // everything after this step is gone from the timetable too
      for (final x in steps.skip(steps.indexOf(st))) {
        x.rolledBack = true;
      }
      remainingAfterApply = null;
    }
    if (mounted) {
      setState(() {});
      await _loadOptions();
    }
  }

  Future<bool> _leave() async {
    if (enough || covered || !hasResult || generating) return true;
    final ok = await confirm(context,
        message: t('ما زالت ${remaining ?? '?'} حصة غير مجدولة. هل تكتفي بهذا الجدول؟', '${remaining ?? '?'} session(s) are still unplaced. Is this timetable enough?'),
        confirmLabel: t('يكفي', 'Enough'));
    if (ok) enough = true;
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = timetableNamesOf(p);
    final st = state;
    final opts = coverageOptions(options?.items ?? const []);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _leave() && context.mounted) Navigator.of(context).pop();
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (!draft)
          AppBanner(
              icon: Icons.lock_rounded,
              text: t('الجدول منشور — أوقف نشره لتوليده من جديد.', 'The timetable is published — unpublish it to generate again.'),
              color: c.warning),
        _Meter(state: st, remaining: remaining, hasResult: hasResult, round: round),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: breakRules,
          onChanged: generating ? null : (v) => setState(() => breakRules = v),
          title: Text(t('اسمح بكسر القيود حسب الأولوية', 'Allow breaking rules by priority'), style: orgText(context, w: FontWeight.w700)),
          subtitle: Text(
            hasResult && round > 0 && breakRules && !st.rulesBroken
                ? t('الخادم الحالي لم يطبّق كسر القيود في الجولة الأخيرة (يحتاج تحديثاً) — طُبّقت التفضيلات المرنة فقط.',
                    'The server did not break rules in the last round (it needs an update) — only soft preferences were relaxed.')
                : t('كل القيود قابلة للكسر بترتيب الأولوية ما عدا: حصتان في المكان نفسه بالوقت نفسه، وعضو يدرّس مقرراً آخر بالوقت نفسه.',
                    'Every rule may be broken in priority order except: two sessions in one room at the same time, and a member teaching another course at the same time.'),
            style: orgText(context, size: 12, color: c.textMedium),
          ),
        ),
        const SizedBox(height: 6),
        if (hasResult && st.broken > 0) ...[
          AppBanner(
              icon: Icons.rule_rounded,
              text: t('كُسرت ${st.broken} قاعدة حسب الأولوية: ', '${st.broken} rule(s) broken by priority: ') +
                  st.brokenByTier.entries.map((e) => '${relaxTierLabel(e.key)} ${e.value}').join(' · '),
              color: c.warning),
          const SizedBox(height: 6),
        ],
        if (covered)
          AppBanner(icon: Icons.verified_rounded, text: t('كل الحصص مجدولة.', 'Every session is placed.'), color: c.success)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            PrimaryButton(
              isLoading: generating,
              icon: Icons.auto_awesome_rounded,
              label: round == 0 && !hasResult ? t('ابدأ التوليد', 'Start generating') : t('جولة جديدة', 'Another round'),
              onPressed: draft && !generating && busyId == null ? _generate : null,
            ),
            if (hasResult)
              OutlinedButton.icon(
                onPressed: generating
                    ? null
                    : () {
                        enough = true;
                        Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.pan_tool_rounded),
                label: Text(t('يكفي', 'Enough')),
              ),
          ]),
        if (generating) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text(t('الخادم يولّد الجدول…', 'The server is generating…'), style: orgText(context, size: 12, color: c.textMedium)),
        ],
        if (hasResult && st.unplaced.isNotEmpty && !covered) ...[
          OrgSectionTitle(t('ما لم يُجدول ولماذا', 'What is unplaced and why'),
              subtitle: remainingAfterApply != null ? t('التفاصيل من آخر توليد', 'Details from the last generation') : null),
          for (final u in st.unplaced) _UnplacedCard(u: u, names: names),
        ],
        if (hasResult && !covered) ...[
          OrgSectionTitle(t('الخيارات', 'Options'), subtitle: t('مرتبة: إعادة الترتيب ← عضو ← موعد ← مكان', 'In order: rearrange → member → time → room')),
          if (loadingOptions)
            const LinearProgressIndicator()
          else if (opts.isEmpty)
            Text(
                options == null
                    ? t('لم تُحسب خيارات بعد', 'No options computed yet')
                    : t('لا خيار يطبّقه الخادم الآن — جرّب جولة جديدة أو أضف عضواً / مكاناً / موعداً من الإعداد.',
                        'No option the server can apply now — try another round or add a member / room / time in the set-up.'),
                style: orgText(context, size: 12.5, color: c.textMedium))
          else
            for (final s in opts) _OptionCard(s: s, busy: busyId == s.id, enabled: draft && busyId == null && !generating, onApply: () => _apply(s)),
          if (draft && p.schedule?['term_id'] != null && st.unplaced.any((u) => u.untouchable)) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: busyId == null && !generating ? _rebalanceAll : null,
              icon: busyId == 'rebalance' ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_tree_rounded),
              label: Text(t('أعد ترتيب كل جداول الفصل معاً', 'Rearrange every timetable of the term together')),
            ),
          ],
          for (final s in coverageAdvice(options?.items ?? const [])) _AdviceCard(s: s, periods: p.periods, onReject: busyId == null ? () => _reject(s) : null),
        ],
        if (steps.isNotEmpty) ...[
          OrgSectionTitle(t('الخطوات والتراجع', 'Steps & rollback')),
          for (final s in steps.reversed)
            RowCard(
              child: Row(children: [
                Icon(s.allTimetables ? Icons.account_tree_rounded : Icons.history_rounded, color: s.rolledBack ? c.textMedium : c.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        '${s.label}${s.allTimetables ? t(' · كل الجداول (${s.changeset?.items.length ?? 0})', ' · all timetables (${s.changeset?.items.length ?? 0})') : ''}',
                        style: orgText(context, w: FontWeight.w700, color: s.rolledBack ? c.textMedium : null))),
                if (s.rolledBack)
                  OrgPill(t('تم التراجع', 'Rolled back'), color: c.textMedium)
                else if (s.revisionBeforeId != null || s.changeset != null)
                  TextButton.icon(onPressed: generating || busyId != null ? null : () => _rollback(s), icon: const Icon(Icons.undo_rounded), label: Text(t('تراجع', 'Roll back'))),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.state, required this.remaining, required this.hasResult, required this.round});
  final CoverageState state;
  final int? remaining;
  final bool hasResult;
  final int round;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final req = state.required;
    final placed = req != null && remaining != null ? req - remaining! : state.placed;
    final rate = req == null || req == 0 || placed == null ? null : placed / req;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(
                  !hasResult
                      ? t('لم يُولَّد الجدول بعد', 'Not generated yet')
                      : remaining == 0
                          ? t('مكتمل', 'Complete')
                          : t('${remaining ?? '?'} حصة غير مجدولة', '${remaining ?? '?'} session(s) unplaced'),
                  style: orgText(context, size: 16, w: FontWeight.w800))),
          if (round > 0) OrgPill(t('الجولة $round', 'Round $round'), color: c.primary),
        ]),
        if (rate != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: rate.clamp(0, 1).toDouble(), minHeight: 10, color: remaining == 0 ? c.success : c.primary),
          ),
          const SizedBox(height: 4),
          Text(t('$placed من $req حصة', '$placed of $req sessions'), style: orgText(context, size: 12, color: c.textMedium)),
        ],
      ]),
    );
  }
}

class _UnplacedCard extends StatelessWidget {
  const _UnplacedCard({required this.u, required this.names});
  final UnplacedSession u;
  final TimetableNames names;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RowCard(
      accent: u.untouchable ? c.danger : c.warning,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${names.course(u.courseId)} · ${u.kind == 'lab' ? t('عملي', 'Lab') : t('محاضرة', 'Lecture')}${u.groupNo == null ? '' : ' G${u.groupNo}'} × ${u.missing}',
                  style: orgText(context, w: FontWeight.w800))),
          if (u.untouchable) OrgPill(t('قيد لا يُكسر', 'Never broken'), color: c.danger),
        ]),
        Text(unplacedReasonText(u.reason), style: orgText(context, size: 12.5)),
        const SizedBox(height: 4),
        Text('${t('الحل بالترتيب: ', 'What to try, in order: ')}${coverageLadder(u).map(coverageStepLabel).join(' ← ')}', style: orgText(context, size: 12, color: c.textMedium)),
      ]),
    );
  }
}

/// A measured advice (a new member, a new room): what it would place, and when / what is needed. Reject only.
class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.s, required this.periods, required this.onReject});
  final ScheduleSuggestion s;
  final List<Map<String, dynamic>> periods;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final before = s.impact.unscheduledBefore, after = s.impact.unscheduledAfter;
    final when = s.type == 'add_staff' ? staffWindowsText(s.config, periods) : '';
    return RowCard(
      accent: c.warning,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          OrgPill(coverageStepLabel(coverageStepOf(s.type)), color: c.warning),
          const SizedBox(width: 6),
          OrgPill(t('نصيحة', 'Advice'), color: c.textMedium),
          const Spacer(),
          if (before != null && after != null && after < before) OrgPill(t('يجدول ${before - after}', 'Places ${before - after}'), color: c.success),
        ]),
        const SizedBox(height: 6),
        Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, style: orgText(context, w: FontWeight.w800)),
        if (s.reason.isNotEmpty) Text(s.reason, style: orgText(context, size: 12.5)),
        if (when.isNotEmpty) Text('${t('مطلوب في: ', 'Needed at: ')}$when', style: orgText(context, size: 12, color: c.textMedium)),
        Text(t('تُنفَّذ خارج الجدول (تعيين عضو / فتح مكان) ثم أعد التوليد.', 'Done outside the timetable (hire a member / open a room), then generate again.'),
            style: orgText(context, size: 12, color: c.textMedium)),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: onReject, child: Text(t('رفض', 'Reject')))),
      ]),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.s, required this.busy, required this.enabled, required this.onApply});
  final ScheduleSuggestion s;
  final bool busy, enabled;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final before = s.impact.unscheduledBefore, after = s.impact.unscheduledAfter;
    return RowCard(
      accent: c.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          OrgPill(coverageStepLabel(coverageStepOf(s.type)), color: c.primary),
          const Spacer(),
          if (before != null && after != null && after < before) OrgPill(t('يجدول ${before - after}', 'Places ${before - after}'), color: c.success),
        ]),
        const SizedBox(height: 6),
        Text(s.title.isEmpty ? suggestionTypeLabel(s.type) : s.title, style: orgText(context, w: FontWeight.w800)),
        if (s.reason.isNotEmpty) Text(s.reason, style: orgText(context, size: 12.5)),
        Text(suggestionTradeOff(s), style: orgText(context, size: 12, color: c.textMedium)),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: PrimaryButton(isLoading: busy, label: t('اعتماد', 'Accept'), onPressed: enabled ? onApply : null),
        ),
      ]),
    );
  }
}
