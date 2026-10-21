// lib/features/org/org_schedule_alternatives.dart — compare real solver alternatives, apply one, or keep the original.
//
// Built only on existing endpoints (org_schedule_router.py / schedule_jobs.py):
//   POST /schedules/{sid}/generate?background=true {settings, keep_locked, seed}  → each run stores a REVISION
//   GET  /schedules/{sid}/runs/{rid}                                             → status · revision_id
//   GET  /schedules/{sid}/revisions[/{rev}]                                      → slots + summary (relaxed, unscheduled …)
//   POST /schedules/{sid}/revisions/{rev}/restore                                → applies one (or puts the original back)
// Hard rules are enforced by the solver and never relaxed; only soft preferences (avoid / prefer) can be. Experience
// is the member's recorded `experience_level` — when it is missing it is reported as "not recorded", never guessed.
//
// Ranking (rankScheduleAlternatives): fewest unplaced sessions → fewest TEACHER preferences relaxed (assistants'
// preferences are relaxed first) → lowest relaxation severity → relaxed people with LESS experience → lower soft cost.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_timetable_parts.dart' show ScheduleResultView, courseName;
import 'org_ui.dart';
import 'org_v3.dart';

/// The solver's soft weights for the two personal preferences (SOFT_WEIGHTS in org_schedule_solver.py).
const _wAvoid = 40.0, _wNotPreferred = 12.0;

/// Measured facts about one generated alternative (or the current timetable).
class AltMetrics {
  AltMetrics({
    required this.unplaced,
    required this.required,
    required this.teacherSeverity,
    required this.assistantSeverity,
    required this.otherSeverity,
    required this.relaxedPeople,
    required this.unknownExperience,
    required this.meanExperience,
    required this.softCost,
  });

  final int unplaced, required, relaxedPeople, unknownExperience;
  final double teacherSeverity, assistantSeverity, otherSeverity, softCost;
  final double? meanExperience;   // of relaxed people WITH a recorded level; null = none recorded

  double get severity => teacherSeverity + assistantSeverity + otherSeverity;

  factory AltMetrics.of(Map<String, dynamic> summary, Map<int, String> roleOf) {
    final stats = asMap(summary['stats']);
    final missing = asMapList(summary['unscheduled']).fold<int>(0, (a, u) => a + asInt(u['missing'] ?? 1));
    final req = asInt(stats['sessions_required'] ?? 0);
    final placed = stats['sessions_placed'];
    var teacher = 0.0, assistant = 0.0, other = 0.0, expSum = 0.0;
    var known = 0, unknown = 0;
    final relaxed = asMapList(summary['relaxed']);
    for (final r in relaxed) {
      final sev = asInt(r['avoided_cell_used'] ?? 0) * _wAvoid + asInt(r['outside_preferred'] ?? 0) * _wNotPreferred;
      switch (roleOf[asInt(r['user_id'])]) {
        case 'teacher':
          teacher += sev;
        case 'teacher_assistant':
          assistant += sev;
        default:
          other += sev;
      }
      if (r['experience_level'] == null) {
        unknown++;
      } else {
        known++;
        expSum += asInt(r['experience_level']);
      }
    }
    return AltMetrics(
      unplaced: placed == null ? missing : (req - asInt(placed)).clamp(0, req),
      required: req,
      teacherSeverity: teacher,
      assistantSeverity: assistant,
      otherSeverity: other,
      relaxedPeople: relaxed.length,
      unknownExperience: unknown,
      meanExperience: known == 0 ? null : expSum / known,
      softCost: (stats['soft_cost'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Lower is better. Unknown experience is neutral: it neither helps nor hurts.
  int compareTo(AltMetrics o) {
    int cmp(num a, num b) => a.compareTo(b);
    for (final c in [
      cmp(unplaced, o.unplaced),
      cmp(teacherSeverity, o.teacherSeverity),
      cmp(severity, o.severity),
      (meanExperience == null || o.meanExperience == null) ? 0 : cmp(meanExperience!, o.meanExperience!),
      cmp(softCost, o.softCost),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }
}

/// Indexes of [all] best first (stable for ties).
List<int> rankScheduleAlternatives(List<AltMetrics> all) {
  final idx = List<int>.generate(all.length, (i) => i);
  idx.sort((a, b) {
    final c = all[a].compareTo(all[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  return idx;
}

/// Why each alternative is good or not, from its numbers compared with the current timetable (never invented).
(List<String>, List<String>) altProsCons(AltMetrics m, AltMetrics? current, {required int changed}) {
  final pros = <String>[], cons = <String>[];
  if (m.unplaced == 0) {
    pros.add(t('كل الحصص موزّعة', 'Every session is placed'));
  } else {
    cons.add(t('${m.unplaced} حصة بلا مكان', '${m.unplaced} session(s) not placed'));
  }
  if (current != null && m.unplaced < current.unplaced) pros.add(t('يضع ${current.unplaced - m.unplaced} حصة إضافية', 'Places ${current.unplaced - m.unplaced} more session(s)'));
  if (m.relaxedPeople == 0) {
    pros.add(t('لم تُخفَّف أي تفضيلات', 'No preference relaxed'));
  } else if (m.teacherSeverity == 0) {
    pros.add(t('التخفيف على المعيدين فقط — تفضيلات المدرسين محفوظة', 'Only assistants\' preferences relaxed — teachers\' kept'));
  } else {
    cons.add(t('يخفّف تفضيلات مدرسين', 'Relaxes teachers\' preferences'));
  }
  if (m.unknownExperience > 0) {
    cons.add(t('الخبرة غير مسجلة لـ ${m.unknownExperience} من المتأثرين (اعتُبرت محايدة)', 'Experience not recorded for ${m.unknownExperience} affected member(s) (treated as neutral)'));
  }
  if (current != null && m.severity < current.severity) pros.add(t('تخفيف أقل من الجدول الحالي', 'Less relaxation than the current timetable'));
  if (changed > 0) cons.add(t('يغيّر $changed حصة عن الجدول الحالي', 'Changes $changed session(s) from the current timetable'));
  return (pros, cons);
}

String _sig(Map s) => [s['course_id'], s['day'], s['period_id'], s['room_id'], s['teacher_id'], s['assistant_id'], s['admin_assistant_id'], s['kind'] ?? 'lecture'].join('|');

/// Sessions of [b] that are not in [a] (multiset).
int slotChanges(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final left = <String, int>{};
  for (final s in a) {
    left.update(_sig(s), (v) => v + 1, ifAbsent: () => 1);
  }
  var changed = 0;
  for (final s in b) {
    final k = _sig(s);
    if ((left[k] ?? 0) > 0) {
      left[k] = left[k]! - 1;
    } else {
      changed++;
    }
  }
  return changed;
}

class _Alt {
  _Alt(this.label, this.help, this.seed, this.senior);
  final String label, help;
  final int seed;
  final bool? senior;   // null = the timetable's own setting
  String status = 'waiting';   // waiting · running · ready · failed · cancelled
  int progress = 0;
  int? revisionId;
  String? error;
  Map<String, dynamic> summary = {};
  List<Map<String, dynamic>> slots = [];
  AltMetrics? metrics;
}

/// Full-screen flow. Returns true when the timetable changed (an alternative was applied).
Future<bool> openScheduleAlternatives(BuildContext context) async {
  final p = context.read<OrgScheduleProvider>();
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider.value(value: p, child: const _AlternativesPage()),
  ));
  return r == true;
}

class _AlternativesPage extends StatefulWidget {
  const _AlternativesPage();

  @override
  State<_AlternativesPage> createState() => _AlternativesPageState();
}

class _AlternativesPageState extends State<_AlternativesPage> {
  late final OrgScheduleProvider p = context.read<OrgScheduleProvider>();
  int get sid => asInt(p.schedule!['id']);
  String get _s => '${p.base}/schedules/$sid';

  String _phase = 'checking';     // checking · blocked · ready · running · done · applying · finished
  String? _blocked;
  int? _originalRev;              // revision equal to the timetable as it was (null + empty slots = an empty timetable)
  late final List<Map<String, dynamic>> _originalSlots = [...p.slots];
  late final Map<String, dynamic> _originalSummary = asMap(p.schedule!['result']);
  late final Map<String, dynamic> _originalSettings = Map<String, dynamic>.from(asMap(p.schedule!['settings']));
  late final Map<int, String> _roleOf = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${m['role']}'};
  late final bool _hasExperience = p.staff.any((m) => m['experience_level'] != null);
  final List<_Alt> _alts = [];
  int? _selected;
  bool _stop = false, _touched = false;
  int? _runId;
  String? _report;
  bool _reportOk = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final sch = p.schedule!;
    String? why;
    if (sch['status'] == 'active') why = t('الجدول منشور — أوقف النشر أو أنشئ نسخة جديدة لاستكشاف البدائل.', 'The timetable is published — unpublish it or create a new version to explore alternatives.');
    if (runIsOpen(p.genRun)) why = t('يجري توليد الجدول الآن — انتظر حتى ينتهي.', 'A generation is running — wait until it ends.');
    if (why == null && _originalSlots.isNotEmpty) {
      // the original must be restorable: it has to be identical to a stored revision
      final list = await orgCall(() => p.api.get('$_s/revisions'), quiet: true);
      final latest = asMapList(list.map['items']).firstOrNull;
      if (latest != null) {
        final rev = await orgCall(() => p.api.get('$_s/revisions/${latest['id']}'), quiet: true);
        final items = asMapList(rev.map['items']);
        if (rev.ok && items.length == _originalSlots.length && slotChanges(_originalSlots, items) == 0) _originalRev = asInt(latest['id']);
      }
      if (_originalRev == null) {
        why = t('في الجدول تعديلات يدوية غير محفوظة كنسخة، فلا يمكن ضمان استرجاعه إذا ألغيت. ثبّت التعديلات أو ولّد الجدول مرة ثم استكشف البدائل.',
            'The timetable has manual edits that are not stored as a version, so it could not be put back if you cancel. Generate once (or keep it as is) and then explore alternatives.');
      }
    }
    if (!mounted) return;
    final senior = _originalSettings['prefer_senior_preferences'] == true;
    _alts.addAll([
      if (_hasExperience) ...[
        _Alt(t('مراعاة الأقدمية', 'Seniority-aware'), t('عند الحاجة تُخفَّف تفضيلات الأقل خبرة أولاً', 'When needed, less experienced members\' preferences are relaxed first'), 7, true),
        _Alt(t('مراعاة الأقدمية · توزيع آخر', 'Seniority-aware · another arrangement'), t('نفس القواعد ببذرة بحث مختلفة', 'Same rules, a different search seed'), 101, true),
        _Alt(t('بدون أقدمية', 'Without seniority'), t('الخبرة لا تؤثر على أي تفضيل يُخفَّف', 'Experience does not affect which preference is relaxed'), 7, false),
      ] else ...[
        _Alt(t('البديل أ', 'Alternative A'), t('لا توجد خبرة مسجلة — معاملة محايدة للجميع', 'No experience recorded — everyone treated neutrally'), 7, null),
        _Alt(t('البديل ب', 'Alternative B'), t('نفس القواعد ببذرة بحث مختلفة', 'Same rules, a different search seed'), 101, null),
      ],
      _Alt(t('البديل ج', 'Alternative C'), t('نفس القواعد ببذرة بحث ثالثة', 'Same rules, a third search seed'), 202, _hasExperience ? senior : null),
    ]);
    setState(() {
      _blocked = why;
      _phase = why == null ? 'ready' : 'blocked';
    });
  }

  Future<void> _generateAll() async {
    setState(() {
      _phase = 'running';
      _stop = false;
    });
    for (final a in _alts) {
      if (_stop) {
        a.status = 'cancelled';
        continue;
      }
      setState(() => a.status = 'running');
      _touched = true;
      final r = await orgCall(
          () => p.api.post('$_s/generate', queryParams: {'background': true}, body: {
                'settings': {'prefer_senior_preferences': a.senior ?? (_originalSettings['prefer_senior_preferences'] == true)},
                'keep_locked': true,
                'seed': a.seed,
              }),
          quiet: true);
      if (!r.ok) {
        setState(() => a
          ..status = 'failed'
          ..error = orgErrorText(r.error!));
        continue;
      }
      _runId = asInt(asMap(r.map['run'])['id']);
      var run = asMap(r.map['run']);
      while (runIsOpen(run)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final g = await orgCall(() => p.api.get('$_s/runs/$_runId'), quiet: true);
        if (g.ok) {
          run = g.map;
          setState(() => a.progress = asInt(run['progress'] ?? 0));
        }
      }
      _runId = null;
      if (run['status'] != 'succeeded' || run['revision_id'] == null) {
        setState(() => a
          ..status = run['status'] == 'cancelled' ? 'cancelled' : 'failed'
          ..error = run['status'] == 'cancelled' ? null : '${run['error'] ?? t('تعذر التوليد', 'Generation failed')}');
        continue;
      }
      final rev = await orgCall(() => p.api.get('$_s/revisions/${run['revision_id']}'), quiet: true);
      if (!mounted) return;
      setState(() {
        if (!rev.ok) {
          a
            ..status = 'failed'
            ..error = orgErrorText(rev.error!);
          return;
        }
        a
          ..status = 'ready'
          ..revisionId = asInt(run['revision_id'])
          ..summary = asMap(rev.map['summary'])
          ..slots = asMapList(rev.map['items'])
          ..metrics = AltMetrics.of(a.summary, _roleOf);
      });
    }
    await _putSettingsBack();
    final ready = _ready;
    setState(() {
      _phase = 'done';
      _selected = ready.isEmpty ? null : ready.first;
    });
  }

  /// generate merges `settings` into the timetable — put the original value back.
  Future<void> _putSettingsBack() async {
    if (!_hasExperience) return;
    final now = await orgCall(() => p.api.get(_s), quiet: true);
    final sch = now.map;
    if (!now.ok || asMap(sch['settings'])['prefer_senior_preferences'] == _originalSettings['prefer_senior_preferences']) return;
    final d = ScheduleDraft.fromJson(sch, allCourses: [for (final l in p.loads) asInt(l['course_id'])]);
    d.settings
      ..clear()
      ..addAll(_originalSettings);
    await orgCall(() => p.api.put(_s, body: d.toBody()), quiet: true);
  }

  /// Ready alternatives, best first.
  List<int> get _ready {
    final idx = [for (var i = 0; i < _alts.length; i++) if (_alts[i].metrics != null) i];
    final order = rankScheduleAlternatives([for (final i in idx) _alts[i].metrics!]);
    return [for (final o in order) idx[o]];
  }

  Future<void> _restoreOriginal() async {
    setState(() => _phase = 'applying');
    var ok = true;
    if (_originalRev != null) {
      ok = (await orgCall(() => p.api.post('$_s/revisions/$_originalRev/restore'), quiet: true)).ok;
    } else {
      // the timetable was empty: remove what the alternatives placed
      final now = await orgCall(() => p.api.get(_s), quiet: true);
      for (final sl in asMapList(now.map['items'])) {
        ok = (await orgCall(() => p.api.delete('$_s/slots/${sl['id']}'), quiet: true)).ok && ok;
      }
    }
    await p.open(sid);
    if (ok) p.schedule?['result'] = _originalSummary;
    _finish(ok, ok ? t('أُعيد الجدول الأصلي كما كان.', 'The original timetable is back as it was.') : t('تعذر استرجاع الجدول الأصلي بالكامل — راجع «النسخ» لاسترجاعه.', 'The original could not be fully restored — use Versions to restore it.'));
  }

  Future<void> _apply(int i) async {
    final a = _alts[i];
    final ok = await appConfirmSimple(context, t('تطبيق «${a.label}»؟', 'Apply “${a.label}”?'),
        t('يحل محل الحصص الحالية في المسودة. يمكنك الرجوع لأي نسخة لاحقاً.', 'It replaces the draft\'s current sessions. You can go back to any version later.'));
    if (!ok || !mounted) return;
    setState(() => _phase = 'applying');
    final r = await orgCall(() => p.api.post('$_s/revisions/${a.revisionId}/restore'), quiet: true);
    await p.open(sid);   // also re-validates the hard rules on the server
    if (!mounted) return;
    if (r.ok) p.schedule?['result'] = a.summary;
    final errors = p.conflicts.where((x) => x['severity'] == 'error').length;
    _finish(r.ok && errors == 0,
        !r.ok
            ? '${t('لم يُطبَّق البديل', 'The alternative was not applied')}: ${orgErrorText(r.error!)}'
            : errors == 0
                ? t('طُبّق البديل — لا تعارضات أساسية.', 'Applied — no hard conflicts.')
                : t('طُبّق البديل لكن الخادم وجد $errors تعارضاً أساسياً — راجعها قبل النشر.', 'Applied, but the server found $errors hard conflict(s) — review them before publishing.'),
        applied: r.ok);
  }

  bool _applied = false;

  void _finish(bool ok, String msg, {bool applied = false}) {
    if (!mounted) return;
    _applied = applied;
    setState(() {
      _phase = 'finished';
      _reportOk = ok;
      _report = msg;
      _touched = false;
    });
  }

  Future<bool> _confirmLeave() async {
    if (_phase == 'running') {
      _stop = true;
      if (_runId != null) await orgCall(() => p.api.post('$_s/runs/$_runId/cancel'), quiet: true);
      return false;
    }
    if (!_touched) return true;
    final go = await appConfirmSimple(context, t('إلغاء البدائل؟', 'Discard the alternatives?'), t('سيُعاد الجدول الأصلي كما كان.', 'The original timetable will be put back.'));
    if (go) await _restoreOriginal();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_touched && _phase != 'running' && _phase != 'applying',
      onPopInvokedWithResult: (did, _) async {
        if (!did) await _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(t('بدائل الجدول', 'Timetable alternatives'))),
        body: Directionality(textDirection: dir, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    switch (_phase) {
      case 'checking':
      case 'applying':
        return const Center(child: CircularProgressIndicator());
      case 'blocked':
        return OrgEmpty(icon: Icons.lock_clock_rounded, title: t('لا يمكن استكشاف البدائل الآن', 'Alternatives aren\'t available right now'), message: _blocked);
      case 'finished':
        return OrgEmpty(
          icon: _reportOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          title: _reportOk ? t('تم', 'Done') : t('انتبه', 'Attention'),
          message: _report,
          actionLabel: t('رجوع', 'Back'),
          onAction: () => Navigator.pop(context, _applied),
        );
    }
    final ready = _ready;
    final current = _originalSummary.isEmpty ? null : AltMetrics.of(_originalSummary, _roleOf);
    final best = ready.isEmpty ? null : ready.first;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Text(
        t('كل بديل توليد حقيقي بالقواعد الأساسية نفسها (لا تداخل لمدرس أو قاعة أو طلاب، والأوقات غير المتاحة ممنوعة). الذي يختلف هو التفضيلات المرنة فقط، وتُخفَّف تفضيلات المعيدين قبل المدرسين.',
            'Each alternative is a real generation under the same hard rules (no double-booked teacher, room or students; unavailable times stay forbidden). Only soft preferences differ, and assistants\' preferences are relaxed before teachers\'.'),
        style: orgText(context, size: 12.5, color: c.textMedium),
      ),
      const SizedBox(height: 12),
      if (current != null) _CurrentCard(m: current),
      for (final i in [...ready, for (var i = 0; i < _alts.length; i++) if (_alts[i].metrics == null) i])
        _AltCard(
          alt: _alts[i],
          recommended: i == best,
          selected: _selected == i,
          current: current,
          changed: _alts[i].metrics == null ? 0 : slotChanges(_originalSlots, _alts[i].slots),
          roleOf: _roleOf,
          onSelect: _alts[i].metrics == null || _phase != 'done' ? null : () => setState(() => _selected = i),
        ),
      if (ready.length > 1) _CompareTable(alts: [for (final i in ready) _alts[i]], best: best == null ? null : _alts[best]),
      const SizedBox(height: 16),
      if (_phase == 'ready')
        PrimaryButton(isLoading: false, icon: Icons.auto_awesome_rounded, iconBefore: true, label: t('ولّد ${_alts.length} بدائل', 'Generate ${_alts.length} alternatives'), onPressed: _generateAll),
      if (_phase == 'running')
        OutlinedButton.icon(onPressed: _confirmLeave, icon: const Icon(Icons.stop_circle_outlined), label: Text(t('إيقاف بعد البديل الحالي', 'Stop'))),
      if (_phase == 'done') ...[
        if (ready.isEmpty)
          Text(t('لم ينجح أي بديل — راجع الأسباب أعلاه.', 'No alternative succeeded — see the reasons above.'), style: orgText(context, color: c.danger)),
        if (_selected != null)
          PrimaryButton(isLoading: false, label: t('تطبيق «${_alts[_selected!].label}»', 'Apply “${_alts[_selected!].label}”'), onPressed: () => _apply(_selected!)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _restoreOriginal, child: Text(t('إلغاء والإبقاء على الجدول الأصلي', 'Cancel and keep the original'))),
      ],
    ]);
  }
}

Future<bool> appConfirmSimple(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('رجوع', 'Back'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('متابعة', 'Continue'))),
        ],
      ),
    ) ==
    true;

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.m});
  final AltMetrics m;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.history_rounded, color: c.textMedium),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            t('الحالي: ${m.required - m.unplaced} من ${m.required} حصة · ${m.relaxedPeople} تفضيل مخفَّف',
                'Current: ${m.required - m.unplaced} of ${m.required} sessions · ${m.relaxedPeople} relaxed'),
            style: orgText(context, size: 12.5, color: c.textMedium),
          ),
        ),
      ]),
    );
  }
}

class _AltCard extends StatelessWidget {
  const _AltCard({
    required this.alt,
    required this.recommended,
    required this.selected,
    required this.current,
    required this.changed,
    required this.roleOf,
    required this.onSelect,
  });

  final _Alt alt;
  final bool recommended, selected;
  final AltMetrics? current;
  final int changed;
  final Map<int, String> roleOf;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<OrgScheduleProvider>();
    final m = alt.metrics;
    final st = '${alt.summary['status'] ?? ''}';
    final people = {for (final x in p.staff) asInt(asMap(x['user'])['id']): '${asMap(x['user'])['name']}'};
    final courseNames = {for (final l in p.loads) asInt(l['course_id']): courseName(l)};
    final (pros, cons) = m == null ? (<String>[], <String>[]) : altProsCons(m, current, changed: changed);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 2 : 1),
        boxShadow: [BoxShadow(color: c.textDark.withValues(alpha: selected ? 0.08 : 0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (onSelect != null) Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: c.primary),
                if (onSelect != null) const SizedBox(width: 8),
                Expanded(child: Text(alt.label, style: orgText(context, w: FontWeight.w800))),
                if (recommended) OrgPill(t('مُوصى به', 'Recommended'), color: c.success, icon: Icons.star_rounded),
                if (m != null && st.isNotEmpty) ...[const SizedBox(width: 6), OrgPill(resultStatusLabels()[st] ?? st, color: m.unplaced == 0 ? c.primary : c.warning)],
              ]),
              Text(alt.help, style: orgText(context, size: 11.5, color: c.textLight)),
              if (alt.status == 'running') ...[const SizedBox(height: 8), LinearProgressIndicator(value: alt.progress == 0 ? null : alt.progress / 100)],
              if (alt.status == 'waiting') Text(t('في الانتظار', 'Waiting'), style: orgText(context, size: 12, color: c.textMedium)),
              if (alt.status == 'cancelled') Text(t('أُوقف', 'Stopped'), style: orgText(context, size: 12, color: c.textMedium)),
              if (alt.status == 'failed') Text(alt.error ?? t('تعذر التوليد', 'Generation failed'), style: orgText(context, size: 12, color: c.danger)),
              if (m != null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  _stat(context, Icons.event_available_rounded, t('${m.required - m.unplaced}/${m.required} حصة', '${m.required - m.unplaced}/${m.required} sessions')),
                  _stat(context, Icons.swap_horiz_rounded, t('$changed تغيير', '$changed changed')),
                  _stat(context, Icons.tune_rounded, t('${m.relaxedPeople} تخفيف', '${m.relaxedPeople} relaxed')),
                ]),
                if (recommended)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_why(m), style: orgText(context, size: 12, color: c.success, w: FontWeight.w700)),
                  ),
                const SizedBox(height: 6),
                for (final x in pros) _line(context, Icons.add_circle_outline_rounded, x, c.success),
                for (final x in cons) _line(context, Icons.remove_circle_outline_rounded, x, c.warning),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(t('التفاصيل: المتأثرون والجدول المقترح', 'Details: affected members and the proposed timetable'), style: orgText(context, size: 12.5, w: FontWeight.w700)),
                    children: [
                      for (final r in _sortedRelaxed(alt.summary, roleOf)) _relaxedTile(context, r, people, roleOf),
                      ScheduleResultView(result: alt.summary, courseNames: courseNames, people: people),
                      _ProposedSlots(slots: alt.slots, courseNames: courseNames, people: people),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  String _why(AltMetrics m) {
    if (m.relaxedPeople == 0 && m.unplaced == 0) return t('الأفضل: كل الحصص موزّعة دون تخفيف أي تفضيل.', 'Best: every session placed without relaxing any preference.');
    if (m.teacherSeverity == 0 && m.unplaced == 0) return t('الأفضل: كل الحصص موزّعة والتخفيف على المعيدين فقط.', 'Best: everything placed, only assistants\' preferences relaxed.');
    return t('الأفضل بين البدائل: أقل حصص بلا مكان ثم أقل تخفيف لتفضيلات المدرسين ثم الأقل خبرة.',
        'Best of the alternatives: fewest unplaced sessions, then the least relaxation of teachers\' preferences, then of less experienced members.');
  }

  static List<Map<String, dynamic>> _sortedRelaxed(Map<String, dynamic> summary, Map<int, String> roleOf) {
    int tier(Map r) => switch (roleOf[asInt(r['user_id'])]) { 'teacher_assistant' => 0, 'teacher' => 1, _ => 2 };
    return asMapList(summary['relaxed'])..sort((a, b) => tier(a).compareTo(tier(b)));
  }

  Widget _relaxedTile(BuildContext context, Map<String, dynamic> r, Map<int, String> people, Map<int, String> roleOf) {
    final c = context.colors;
    final uid = asInt(r['user_id']);
    final role = roleOf[uid];
    final avoided = asInt(r['avoided_cell_used'] ?? 0), outside = asInt(r['outside_preferred'] ?? 0);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(role == 'teacher' ? Icons.school_rounded : Icons.support_agent_rounded, color: role == 'teacher' ? c.warning : c.primary),
      title: Text('${people[uid] ?? '#$uid'} · ${role == 'teacher' ? t('مدرس', 'Teacher') : role == 'teacher_assistant' ? t('معيد', 'Teaching assistant') : t('عضو', 'Member')}',
          style: orgText(context, size: 13, w: FontWeight.w700)),
      subtitle: Text(
        [
          if (avoided > 0) t('$avoided فترة في أوقات طلب تجنّبها', '$avoided period(s) in times they asked to avoid'),
          if (outside > 0) t('$outside فترة خارج أوقاته المفضّلة', '$outside period(s) outside their preferred times'),
          r['experience_level'] == null ? t('الخبرة غير مسجلة', 'Experience not recorded') : t('الخبرة المسجلة: ${r['experience_level']}', 'Recorded experience: ${r['experience_level']}'),
        ].join(' · '),
        style: orgText(context, size: 11.5, color: c.textMedium),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData i, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: context.colors.textMedium),
        const SizedBox(width: 4),
        Text(s, style: orgText(context, size: 12, color: context.colors.textMedium)),
      ]);

  Widget _line(BuildContext context, IconData i, String s, Color col) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 15, color: col),
          const SizedBox(width: 6),
          Expanded(child: Text(s, style: orgText(context, size: 12))),
        ]),
      );
}

class _ProposedSlots extends StatelessWidget {
  const _ProposedSlots({required this.slots, required this.courseNames, required this.people});
  final List<Map<String, dynamic>> slots;
  final Map<int, String> courseNames, people;

  @override
  Widget build(BuildContext context) {
    final p = context.read<OrgScheduleProvider>();
    final c = context.colors;
    final periods = {for (final x in p.periods) asInt(x['id']): x};
    final rooms = {for (final x in p.rooms) asInt(x['id']): '${x['name'] ?? ''}'};
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final s in slots) {
      byDay.putIfAbsent('${s['day']}', () => []).add(s);
    }
    final days = orgDays.where(byDay.containsKey);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(t('الجدول المقترح', 'Proposed timetable'), style: orgText(context, w: FontWeight.w800))),
      for (final d in days) ...[
        Text(dayLabels()[d] ?? d, style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.primary)),
        for (final s in byDay[d]!..sort((a, b) => asInt(periods[asInt(a['period_id'])]?['order'] ?? 0).compareTo(asInt(periods[asInt(b['period_id'])]?['order'] ?? 0))))
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, bottom: 2),
            child: Text(
              '${periods[asInt(s['period_id'])]?['label'] ?? ''} ${periods[asInt(s['period_id'])]?['start_time'] ?? ''} · ${courseNames[asInt(s['course_id'])] ?? '#${s['course_id']}'}'
              '${s['kind'] == 'lab' ? ' (${t('عملي', 'lab')})' : ''} · ${rooms[asInt(s['room_id'])] ?? ''} · ${people[asInt(s['teacher_id'])] ?? ''}',
              style: orgText(context, size: 11.5, color: c.textMedium),
            ),
          ),
      ],
    ]);
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.alts, required this.best});
  final List<_Alt> alts;
  final _Alt? best;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    TextStyle h = orgText(context, size: 12, w: FontWeight.w800);
    TextStyle v(bool b) => orgText(context, size: 12, w: b ? FontWeight.w800 : FontWeight.w500, color: b ? c.success : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OrgSectionTitle(t('مقارنة', 'Compare'), padding: const EdgeInsets.fromLTRB(4, 8, 4, 6)),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          columnSpacing: 18,
          columns: [
            DataColumn(label: Text(t('البديل', 'Alternative'), style: h)),
            DataColumn(label: Text(t('بلا مكان', 'Unplaced'), style: h), numeric: true),
            DataColumn(label: Text(t('تخفيف للمدرسين', 'Teacher relax.'), style: h), numeric: true),
            DataColumn(label: Text(t('تخفيف للمعيدين', 'Assistant relax.'), style: h), numeric: true),
            DataColumn(label: Text(t('متوسط خبرة المتأثرين', 'Affected exp.'), style: h), numeric: true),
            DataColumn(label: Text(t('التكلفة المرنة', 'Soft cost'), style: h), numeric: true),
          ],
          rows: [
            for (final a in alts)
              DataRow(cells: [
                DataCell(Text(a.label, style: v(a == best))),
                DataCell(Text('${a.metrics!.unplaced}', style: v(a == best))),
                DataCell(Text(a.metrics!.teacherSeverity.toStringAsFixed(0), style: v(a == best))),
                DataCell(Text(a.metrics!.assistantSeverity.toStringAsFixed(0), style: v(a == best))),
                DataCell(Text(a.metrics!.meanExperience?.toStringAsFixed(1) ?? '—', style: v(a == best))),
                DataCell(Text(a.metrics!.softCost.toStringAsFixed(1), style: v(a == best))),
              ]),
          ],
        ),
      ),
    ]);
  }
}
