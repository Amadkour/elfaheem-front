// lib/features/org/org_schedule_insights.dart — what the CP-SAT engine explains, before and after a generation.
//
//   PreflightReport / PreflightFinding   pure: GET …/preflight — impossible inputs in plain words with their fix
//   DataHealthCard                       the data-health panel (blockers · warnings · demand vs supply · engine)
//   ruleShort / coreText                 pure: a rule name → a few words; "blocked by A + B" for unscheduled[].core
//   ExplainRows                          the per-option reasons of an unplaced session (unscheduled[].explain)
//   QualityReport                        pure: workload balance · idle gaps · same-day repeats · room use → score 0–100
//   QualityCard                          the quality report after a generation
//   WhyHere / WhyHereSection             GET …/slots/{id}/why — why a placed session sits where it is
//
// Everything pure is tested in test/org/org_insights_test.dart; the widgets in test/ui/insights_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show RowCard;
import 'org_common.dart' show dayLabels;
import 'org_providers.dart' show orgDays;
import 'org_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pre-flight (data health)
// ═════════════════════════════════════════════════════════════════════════════

class PreflightFinding {
  const PreflightFinding({required this.code, required this.severity, required this.textAr, required this.textEn, required this.fixAr, required this.fixEn, this.courseId, this.userId, this.roomId, this.detail = const {}});
  final String code, severity, textAr, textEn, fixAr, fixEn;
  final int? courseId, userId, roomId;
  final Map<String, dynamic> detail;

  bool get blocker => severity == 'blocker';
  String get text => t(textAr, textEn);
  String get fix => t(fixAr, fixEn);

  factory PreflightFinding.of(Map<String, dynamic> m) => PreflightFinding(
        code: '${m['code']}',
        severity: '${m['severity'] ?? 'warning'}',
        textAr: '${m['text_ar'] ?? m['text_en'] ?? m['code']}',
        textEn: '${m['text_en'] ?? m['text_ar'] ?? m['code']}',
        fixAr: '${m['fix_ar'] ?? m['fix_en'] ?? ''}',
        fixEn: '${m['fix_en'] ?? m['fix_ar'] ?? ''}',
        courseId: m['course_id'] == null ? null : asInt(m['course_id']),
        userId: m['user_id'] == null ? null : asInt(m['user_id']),
        roomId: m['room_id'] == null ? null : asInt(m['room_id']),
        detail: asMap(m['detail']),
      );
}

class PreflightReport {
  const PreflightReport({required this.findings, required this.summary, this.engine});
  final List<PreflightFinding> findings; // blockers first
  final Map<String, dynamic> summary; // sessions · periods_needed · cells · rooms · room_cells · utilization_pct · teachers · sessions_by_kind · cohorts
  final String? engine;

  int get blockers => findings.where((f) => f.blocker).length;
  int get warnings => findings.length - blockers;
  bool get clean => findings.isEmpty;
  int get sessions => asInt(summary['sessions']);
  int get utilizationPct => asInt(summary['utilization_pct']);

  factory PreflightReport.of(Map<String, dynamic> m) {
    final items = [for (final x in asMapList(m['findings'])) PreflightFinding.of(x)]..sort((a, b) => (a.blocker ? 0 : 1).compareTo(b.blocker ? 0 : 1));
    return PreflightReport(findings: items, summary: asMap(m['summary']), engine: m['engine'] as String?);
  }
}

/// The widest a Wrap item may be: the screen minus the card's own padding and margins.
double wrapWidth(BuildContext context) => (MediaQuery.sizeOf(context).width - 96).clamp(160.0, 900.0);

String engineLabel(String? engine) => switch (engine) {
      'cpsat' => t('محرّك CP-SAT (حل بالقيود)', 'CP-SAT constraint solver'),
      'heuristic' => t('المحرّك التقريبي', 'Heuristic engine'),
      _ => '',
    };

/// The data-health panel shown before (and next to) a generation. [names] resolve ids in the fix lines.
class DataHealthCard extends StatelessWidget {
  const DataHealthCard({super.key, required this.report, this.courseNames = const {}, this.people = const {}, this.rooms = const {}, this.onFix});
  final PreflightReport report;
  final Map<int, String> courseNames, people, rooms;

  /// tapped a finding (open the course / member / room it names)
  final void Function(PreflightFinding f)? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.blockers > 0 ? c.danger : (r.warnings > 0 ? c.warning : c.success);
    final s = r.summary;
    String who(PreflightFinding f) => [
          if (f.courseId != null) courseNames[f.courseId] ?? '#${f.courseId}',
          if (f.userId != null) people[f.userId] ?? '#${f.userId}',
          if (f.roomId != null) rooms[f.roomId] ?? '#${f.roomId}',
        ].join(' · ');
    return RowCard(
      accent: col,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.clean ? Icons.health_and_safety_rounded : (r.blockers > 0 ? Icons.report_rounded : Icons.warning_amber_rounded), color: col, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.clean
                  ? t('البيانات سليمة — جاهزة للتوليد', 'Data is healthy — ready to generate')
                  : r.blockers > 0
                      ? t('${r.blockers} مانع يوقف التوليد الكامل', '${r.blockers} blocker(s) prevent a complete timetable')
                      : t('${r.warnings} تنبيه على البيانات', '${r.warnings} data warning(s)'),
              style: orgText(context, w: FontWeight.w800, color: col),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // chips never grow past the card: each is bounded to the screen width (a Wrap gives none; a LayoutBuilder
        // is not allowed inside the card's intrinsic-height row)
        Wrap(spacing: 8, runSpacing: 4, children: [
          _chip(context, Icons.event_note_rounded, t('${r.sessions} حصة', '${r.sessions} sessions'), wrapWidth(context)),
          _chip(context, Icons.grid_on_rounded, t('${asInt(s['cells'])} خانة × ${asInt(s['rooms'])} قاعة', '${asInt(s['cells'])} cells × ${asInt(s['rooms'])} rooms'), wrapWidth(context)),
          _chip(context, Icons.speed_rounded, t('استغلال القاعات ${r.utilizationPct}٪', 'Room use ${r.utilizationPct}%'), wrapWidth(context)),
          if (asInt(s['cohorts']) > 0) _chip(context, Icons.groups_rounded, t('${asInt(s['cohorts'])} مجموعة طلاب', '${asInt(s['cohorts'])} student cohorts'), wrapWidth(context)),
          if (engineLabel(r.engine).isNotEmpty) _chip(context, Icons.memory_rounded, engineLabel(r.engine), wrapWidth(context)),
        ]),
        for (final f in r.findings.take(12))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onFix == null ? null : () => onFix!(f),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(f.blocker ? Icons.block_rounded : Icons.info_outline_rounded, size: 16, color: f.blocker ? c.danger : c.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.text, style: orgText(context, size: 12.5, w: FontWeight.w700)),
                    if (who(f).isNotEmpty) Text(who(f), style: orgText(context, size: 11.5, color: c.textMedium)),
                    if (f.fix.isNotEmpty) Text('${t('الحل', 'Fix')}: ${f.fix}', style: orgText(context, size: 12, color: c.textMedium)),
                  ]),
                ),
              ]),
            ),
          ),
        if (r.findings.length > 12) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('+${r.findings.length - 12} أخرى', '+${r.findings.length - 12} more'), style: orgText(context, size: 12, color: c.textLight))),
      ]),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text, double maxWidth) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.isFinite ? maxWidth : 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c.textMedium),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11.5, color: c.textMedium))),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Explanations (unscheduled[].core / explain · why-here rules)
// ═════════════════════════════════════════════════════════════════════════════

/// A solver rule in a few words (short form for chips and "blocked by" lines).
String ruleShort(String rule) => switch (rule) {
      'teacher_busy' => t('المدرس مشغول', 'instructor busy'),
      'teacher_unavailable' => t('المدرس غير متاح', 'instructor unavailable'),
      'teacher_day_limit' => t('الحد اليومي للمدرس', 'instructor daily limit'),
      'teacher_week_limit' => t('الحد الأسبوعي للمدرس', 'instructor weekly cap'),
      'students_clash' => t('طلاب في حصة أخرى', 'students in another session'),
      'students_unavailable' => t('الطلاب غير متاحين', 'students unavailable'),
      'students_busy_elsewhere' => t('الطلاب في جدول آخر', 'students in another timetable'),
      'course_already_there' => t('حصة أخرى للمقرر', 'another session of the course'),
      'rooms_busy' => t('القاعات محجوزة', 'rooms taken'),
      'room_unavailable' => t('القاعة غير متاحة', 'room unavailable'),
      'no_room_fits' => t('لا قاعة مناسبة', 'no fitting room'),
      'travel_gap' => t('وقت الانتقال بين المباني', 'travel time between buildings'),
      'no_consecutive_periods' => t('لا فترات متتالية كافية', 'not enough consecutive periods'),
      'time_limit' => t('انتهى وقت الحل', 'solver ran out of time'),
      'no_free_cell' => t('لا خانة حرة', 'no free cell'),
      _ => rule.replaceAll('_', ' '),
    };

/// "Blocked by: instructor busy + rooms taken" — the smallest set of rules that together block every option.
String coreText(List<String> core) {
  if (core.isEmpty) return '';
  if (core.length == 1 && core.first == 'time_limit') return t('كانت هناك أوقات حرة — انتهى وقت الحل قبل وضعها؛ ولّد مرة أخرى', 'Free times existed — the solver ran out of time; generate again');
  return '${t('يمنعها معاً', 'Blocked by')}: ${core.map(ruleShort).join(' + ')}';
}

/// One line per option of unscheduled[].explain: "Sunday · P1: instructor busy (Physics II)".
class ExplainRows extends StatelessWidget {
  const ExplainRows({super.key, required this.rows, this.courseNames = const {}, this.periodLabel, this.max = 8});
  final List<Map<String, dynamic>> rows;
  final Map<int, String> courseNames;
  final String Function(int periodId)? periodLabel;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final x in rows.take(max))
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${labels['${x['day']}'] ?? x['day']} · ${[for (final p in (x['period_ids'] as List? ?? const [])) periodLabel?.call(asInt(p)) ?? 'P$p'].join('+')}: '
            '${[for (final r in (x['rules'] as List? ?? const [])) ruleShort('$r')].join('، ')}'
            '${_blockers(x)}',
            style: orgText(context, size: 11.5, color: c.textMedium),
          ),
        ),
      if (rows.length > max) Text(t('+${rows.length - max} وقتاً آخر', '+${rows.length - max} more times'), style: orgText(context, size: 11.5, color: c.textLight)),
    ]);
  }

  String _blockers(Map<String, dynamic> x) {
    final names = [
      for (final b in asMapList(x['blocked_by']))
        if (b['course_id'] != null) courseNames[asInt(b['course_id'])] ?? '#${b['course_id']}' else if (b['external'] == true) t('جدول آخر', 'another timetable'),
    ];
    return names.isEmpty ? '' : ' (${names.toSet().take(2).join('، ')})';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Quality report
// ═════════════════════════════════════════════════════════════════════════════

/// Fairness and quality of a timetable, from its slots alone. Score 0–100:
///   40 · workload balance (1 − coefficient of variation of periods per instructor / TA, clipped)
///   30 · compactness (1 − idle periods between a person's first and last session of a day ÷ taught periods)
///   30 · spread (1 − repeats of a course group on one day ÷ sessions)
/// Room use (busy room-cells ÷ available exclusive room-cells) is reported, not scored: both 30 % and 95 % can be right.
class QualityReport {
  const QualityReport({required this.score, required this.balance, required this.compactness, required this.spread, required this.utilizationPct, required this.workload, required this.idle, required this.repeats, required this.sessions});
  final int score;
  final double balance, compactness, spread; // 0–1
  final int utilizationPct;
  final Map<int, int> workload; // person → periods a week (instructors and TAs)
  final int idle, repeats, sessions;

  /// [periods] with id · order; [days] the teaching days; [rooms] active rooms ({id, exclusive}).
  factory QualityReport.of(List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods, {List<String> days = const [], List<Map<String, dynamic>> rooms = const []}) {
    final order = <int, int>{};
    final sorted = [...periods]..sort((a, b) => asInt(a['order']).compareTo(asInt(b['order'])));
    for (final (i, p) in sorted.indexed) {
      order[asInt(p['id'])] = i;
    }
    final load = <int, int>{};
    final perDay = <(int, String), Set<int>>{}; // (person, day) → period indexes
    final groupDay = <(int, String, int?, String), int>{}; // (course, kind, group, day) → blocks
    final blocks = <String>{};
    final roomCells = <(int, String, int)>{};
    for (final s in slots) {
      final pi = order[asInt(s['period_id'])];
      for (final k in const ['teacher_id', 'assistant_id']) {
        if (s[k] == null) continue;
        final u = asInt(s[k]);
        load[u] = (load[u] ?? 0) + 1;
        if (pi != null) (perDay[(u, '${s['day']}')] ??= {}).add(pi);
      }
      if (s['room_id'] != null) roomCells.add((asInt(s['room_id']), '${s['day']}', asInt(s['period_id'])));
      final key = '${s['block_id'] ?? 'slot-${s['id']}'}|${s['course_id']}';
      if (blocks.add(key)) {
        final g = (asInt(s['course_id']), '${s['kind'] ?? 'lecture'}', s['group_no'] == null ? null : asInt(s['group_no']), '${s['day']}');
        groupDay[g] = (groupDay[g] ?? 0) + 1;
      }
    }
    final sessions = blocks.length;
    // balance
    double balance = 1;
    if (load.length > 1) {
      final mean = load.values.fold<int>(0, (a, b) => a + b) / load.length;
      final varc = load.values.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / load.length;
      final cv = mean == 0 ? 0 : (varc <= 0 ? 0 : _sqrt(varc) / mean);
      balance = (1 - cv).clamp(0, 1).toDouble();
    }
    // idle periods between first and last of a day
    var idle = 0, taught = 0;
    for (final set in perDay.values) {
      taught += set.length;
      if (set.length < 2) continue;
      final lo = set.reduce((a, b) => a < b ? a : b), hi = set.reduce((a, b) => a > b ? a : b);
      idle += (hi - lo + 1) - set.length;
    }
    final compactness = taught == 0 ? 1.0 : (1 - idle / taught).clamp(0, 1).toDouble();
    // same-day repeats of one course group
    final repeats = groupDay.values.fold<int>(0, (a, n) => a + (n > 1 ? n - 1 : 0));
    final spread = sessions == 0 ? 1.0 : (1 - repeats / sessions).clamp(0, 1).toDouble();
    final exclusive = rooms.where((r) => r['exclusive'] != false && r['is_active'] != false).length;
    final cells = days.length * periods.length * exclusive;
    final util = cells == 0 ? 0 : (100 * roomCells.length / cells).round();
    final score = sessions == 0 ? 0 : (40 * balance + 30 * compactness + 30 * spread).round().clamp(0, 100);
    return QualityReport(score: score, balance: balance, compactness: compactness, spread: spread, utilizationPct: util, workload: load, idle: idle, repeats: repeats, sessions: sessions);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    var x = v;
    for (var i = 0; i < 40; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  /// The busiest people first: (person, periods).
  List<(int, int)> get topWorkload => (workload.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1)));
}

String qualityLabel(int score) => score >= 85 ? t('ممتاز', 'Excellent') : score >= 70 ? t('جيد', 'Good') : score >= 50 ? t('مقبول', 'Fair') : t('ضعيف', 'Poor');

class QualityCard extends StatelessWidget {
  const QualityCard({super.key, required this.report, this.people = const {}, this.relaxed = 0, this.broken = 0, this.solver});
  final QualityReport report;
  final Map<int, String> people;
  final int relaxed, broken; // preferences relaxed · rules broken on purpose (from result)
  final Map<String, dynamic>? solver; // result.solver (status, wall_s, deterministic)

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final col = r.score >= 70 ? c.success : (r.score >= 50 ? c.warning : c.danger);
    String pct(double v) => '${(100 * v).round()}%';
    final top = r.topWorkload.take(5).toList();
    final maxLoad = top.isEmpty ? 1 : top.first.$2;
    return RowCard(
      accent: col,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.14), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
            child: Text('${r.score}', style: orgText(context, size: 15, w: FontWeight.w800, color: col)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('جودة الجدول', 'Timetable quality')} · ${qualityLabel(r.score)}', style: orgText(context, w: FontWeight.w800)),
              Text(
                t('توازن العبء ${pct(r.balance)} · تماسك الأيام ${pct(r.compactness)} · توزيع المقررات ${pct(r.spread)} · استغلال القاعات ${r.utilizationPct}٪',
                    'Workload balance ${pct(r.balance)} · compact days ${pct(r.compactness)} · course spread ${pct(r.spread)} · room use ${r.utilizationPct}%'),
                style: orgText(context, size: 11.5, color: c.textMedium),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 4, children: [
            for (final w in <Widget>[
          Text(t('${r.sessions} حصة', '${r.sessions} sessions'), style: orgText(context, size: 12, color: c.textMedium)),
          Text(t('${r.idle} فترة فراغ', '${r.idle} idle period(s)'), style: orgText(context, size: 12, color: r.idle > 0 ? c.warning : c.textMedium)),
          Text(t('${r.repeats} تكرار في اليوم نفسه', '${r.repeats} same-day repeat(s)'), style: orgText(context, size: 12, color: r.repeats > 0 ? c.warning : c.textMedium)),
          if (relaxed > 0) Text(t('$relaxed تفضيل غير مُلبّى', '$relaxed preference(s) relaxed'), style: orgText(context, size: 12, color: c.warning)),
          if (broken > 0) Text(t('$broken قاعدة كُسرت باقتراح', '$broken rule(s) broken as proposals'), style: orgText(context, size: 12, color: c.warning)),
          if (solver != null && solver!['status'] != null)
            Text(
              '${solver!['status'] == 'OPTIMAL' ? t('حل أمثل', 'Optimal') : t('أفضل حل في الوقت', 'Best within the time')} · ${solver!['wall_s'] ?? '?'} ${t('ث', 's')}'
              '${solver!['deterministic'] == true ? ' · ${t('قابل للتكرار', 'reproducible')}' : ''}',
              style: orgText(context, size: 12, color: c.textMedium),
            ),
            ])
              ConstrainedBox(constraints: BoxConstraints(maxWidth: wrapWidth(context)), child: w),
        ]),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t('العبء الأسبوعي (فترات)', 'Weekly load (periods)'), style: orgText(context, size: 12, w: FontWeight.w800, color: c.textMedium)),
          for (final (uid, n) in top)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                SizedBox(width: 120, child: Text(people[uid] ?? '#$uid', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12))),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: n / maxLoad, minHeight: 8, color: c.primary, backgroundColor: c.primary.withValues(alpha: 0.12)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 24, child: Text('$n', textAlign: TextAlign.end, style: orgText(context, size: 12, w: FontWeight.w700))),
              ]),
            ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Why here?
// ═════════════════════════════════════════════════════════════════════════════

class WhyHere {
  const WhyHere({required this.found, required this.options, required this.free, required this.blockedBy, required this.alternatives, required this.here, this.brokenRules = const []});
  final bool found;
  final int options, free;
  final Map<String, int> blockedBy; // rule → how many other times it blocks
  final List<Map<String, dynamic>> alternatives; // free {day, period_ids}
  final Map<String, dynamic> here; // teacher_prefers · teacher_avoids · teacher_unavailable · org_avoids · students · room_capacity · room_is_smallest_fit · locked
  final List<Map<String, dynamic>> brokenRules;

  factory WhyHere.of(Map<String, dynamic> m) => WhyHere(
        found: m['found'] != false && m['known_load'] != false,
        options: asInt(m['options']),
        free: asInt(m['free']),
        blockedBy: {for (final e in asMap(m['blocked_by']).entries) e.key: asInt(e.value)},
        alternatives: asMapList(m['alternatives']),
        here: asMap(m['here']),
        brokenRules: asMapList(m['broken_rules']),
      );

  /// The sentences shown to the admin, most useful first.
  List<String> get facts {
    final out = <String>[];
    if (here['teacher_prefers'] == true) out.add(t('وقت يفضّله المدرس', 'A time the instructor prefers'));
    if (here['teacher_avoids'] == true) out.add(t('وقت يتجنّبه المدرس — لم يتوفر أفضل', 'A time the instructor avoids — nothing better was free'));
    if (here['teacher_unavailable'] == true) out.add(t('المدرس غير متاح هنا (قاعدة كُسرت أو تجاوز)', 'The instructor is unavailable here (a broken rule or an override)'));
    if (here['org_avoids'] == true) out.add(t('وقت تتجنّبه المؤسسة', 'A time the organization avoids'));
    if (here['room_capacity'] != null) {
      out.add(here['room_is_smallest_fit'] == true
          ? t('أصغر قاعة تكفي ${here['students']} طالباً (سعة ${here['room_capacity']})', 'The smallest room that fits ${here['students']} students (capacity ${here['room_capacity']})')
          : t('قاعة بسعة ${here['room_capacity']} لـ ${here['students']} طالباً', 'A room for ${here['room_capacity']} with ${here['students']} students'));
    }
    if (here['locked'] == true) out.add(t('مثبتة يدوياً — المولّد لا يحركها', 'Pinned by hand — the generator never moves it'));
    out.add(free == 0
        ? t('لا وقت آخر متاح لهذه الحصة الآن', 'No other time is free for this session right now')
        : t('$free من $options وقتاً آخر متاح أيضاً', '$free of $options other times are also free'));
    return out;
  }
}

class WhyHereSection extends StatelessWidget {
  const WhyHereSection({super.key, required this.why, this.periodLabel});
  final WhyHere why;
  final String Function(int periodId)? periodLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    if (!why.found) return Text(t('لا يمكن تفسير هذه الحصة: عبء المقرر غير معروف.', 'Cannot explain this session: its course load is unknown.'), style: orgText(context, size: 12.5, color: c.textMedium));
    final blocked = why.blockedBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final f in why.facts)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline_rounded, size: 15, color: c.textMedium),
            const SizedBox(width: 6),
            Expanded(child: Text(f, style: orgText(context, size: 12.5))),
          ]),
        ),
      if (blocked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${t('الأوقات الأخرى يمنعها', 'Other times are blocked by')}: ${blocked.take(4).map((e) => '${e.value} × ${ruleShort(e.key)}').join('، ')}', style: orgText(context, size: 12, color: c.textMedium)),
        ),
      if (why.alternatives.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${t('بدائل حرة', 'Free alternatives')}: ${why.alternatives.take(4).map((a) => '${labels['${a['day']}'] ?? a['day']} ${[for (final p in (a['period_ids'] as List? ?? const [])) periodLabel?.call(asInt(p)) ?? 'P$p'].join('+')}').join('، ')}',
            style: orgText(context, size: 12, color: c.textMedium),
          ),
        ),
      for (final b in why.brokenRules) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t('قاعدة كُسرت هنا', 'Rule broken here')}: ${ruleShort('${b['rule']}')}', style: orgText(context, size: 12, color: c.warning))),
    ]);
  }
}

/// Keeps `orgDays` referenced for callers that import this file for day order.
List<String> get insightDays => orgDays;
