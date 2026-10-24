// lib/features/org/org_schedule_remedies.dart — every conflict of the timetable with ranked ways out.
//
//   RemedyReport / RemedyItem   pure: GET …/schedules/{sid}/remedies — {items: [{key, conflict, actions}]}
//   fetchRemedies / applyRemedy GET …/remedies · POST …/remedies/apply {action, expected_version, force, override_reason}
//   RemediesPanel               the conflicts list of the Quick Actions sheet: each conflict + its ranked actions
//                               (Accept on the automatic ones; "by hand" on the rest). Never a conflict without a way out.
//
// Pure parts are tested in test/org/org_reassign_test.dart; the panel in test/ui/reassign_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../admin/admin_common.dart';
import 'org_common.dart' show dayLabels;
import 'org_providers.dart';
import 'org_schedule_insights.dart' show ActionOption, RankedActions;
import 'org_ui.dart' show orgText;
import 'org_v3.dart';

class RemedyItem {
  const RemedyItem({required this.key, required this.conflict, required this.actions});
  final String key;
  final Map<String, dynamic> conflict;
  final List<ActionOption> actions;

  String get type => '${conflict['type'] ?? ''}';
  String get severity => '${conflict['severity'] ?? 'error'}';
  bool get hard => severity == 'error';
  bool get automatic => actions.any((a) => a.auto);
  ActionOption? get best => actions.where((a) => a.auto).firstOrNull;
  String? get day => conflict['day'] as String?;
  List<int> get courseIds => [for (final i in (conflict['course_ids'] as List? ?? const [])) asInt(i)];
  List<int> get slotIds => [for (final i in (conflict['slot_ids'] as List? ?? const [])) asInt(i)];

  /// the conflict in words (server text, else the type)
  String get text => conflict['text_ar'] != null ? t('${conflict['text_ar']}', '${conflict['text_en'] ?? conflict['text_ar']}') : conflictTypeText(type);

  /// "P2 (10:00–11:30)" of the first period the server described
  String get when {
    final times = asMapList(conflict['times']);
    if (times.isEmpty) return '';
    final x = times.first;
    return '${x['label'] ?? ''}${x['start_time'] != null ? ' (${x['start_time']}–${x['end_time']})' : ''}';
  }

  factory RemedyItem.of(Map<String, dynamic> m) => RemedyItem(key: '${m['key'] ?? ''}', conflict: asMap(m['conflict']), actions: ActionOption.listOf(m['actions']));
}

class RemedyReport {
  const RemedyReport({required this.items, this.errors = 0, this.warnings = 0, this.soft = 0, this.automatic = 0, this.version = 0});
  final List<RemedyItem> items;
  final int errors, warnings, soft, automatic, version;

  bool get clean => items.isEmpty;
  List<RemedyItem> get hard => [for (final i in items) if (i.hard) i];

  factory RemedyReport.of(Map<String, dynamic> m) => RemedyReport(
        items: [for (final x in asMapList(m['items'])) RemedyItem.of(x)],
        errors: asInt(m['errors']),
        warnings: asInt(m['warnings']),
        soft: asInt(m['soft']),
        automatic: asInt(m['automatic']),
        version: asInt(m['version']),
      );
}

/// GET …/remedies. `missing` = an older server (no such route).
Future<({RemedyReport? report, bool missing})> fetchRemedies(OrgScheduleProvider p) async {
  final id = p.schedule?['id'];
  if (id == null) return (report: null, missing: false);
  final r = await orgCall(() => p.api.get('${p.base}/schedules/$id/remedies'), quiet: true);
  if (r.ok) return (report: RemedyReport.of(r.map), missing: false);
  return (report: null, missing: r.error != null && orgEndpointMissing(r.error!));
}

/// POST …/remedies/apply. Reloads the timetable (slots + conflicts) when it worked. The server answers
/// `schedule_conflict` (409) when a slot change still clashes — the caller may retry with [force].
Future<OrgCall> applyRemedy(OrgScheduleProvider p, ActionOption a, {bool force = false, String? overrideReason}) async {
  final id = p.schedule?['id'];
  if (id == null) return const OrgCall(null);
  final r = await orgCall(
      () => p.api.post('${p.base}/schedules/$id/remedies/apply', body: {
            'action': a.toJson(),
            'expected_version': ?p.schedule?['version'],
            if (force) 'force': true,
            'override_reason': ?overrideReason,
          }),
      quiet: true);
  if (r.ok || r.code == 'stale_version') await p.open(asInt(id));
  return r;
}

/// The conflicts of the timetable, each with its ranked ways out. [onAccept] applies an automatic action (null =
/// read-only); [busy] holds the conflict keys with a request in flight.
class RemediesPanel extends StatelessWidget {
  const RemediesPanel({super.key, required this.report, this.courseNames = const {}, this.onAccept, this.busy = const {}, this.limit = 30});
  final RemedyReport report;
  final Map<int, String> courseNames;
  final void Function(RemedyItem item, ActionOption a)? onAccept;
  final Set<String> busy;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = dayLabels();
    final items = report.items.take(limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (report.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 18, color: c.success),
            const SizedBox(width: 8),
            Expanded(child: Text(t('لا تعارضات', 'No conflicts'), style: orgText(context, size: 12.5, color: c.success))),
          ]),
        ),
      for (final x in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (x.hard ? c.danger : c.warning).withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(x.hard ? Icons.error_rounded : Icons.warning_amber_rounded, size: 18, color: x.hard ? c.danger : c.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.text, style: orgText(context, w: FontWeight.w700)),
                    Text(
                      [
                        if (x.day != null) labels[x.day!] ?? x.day!,
                        if (x.when.isNotEmpty) x.when,
                        x.courseIds.map((i) => courseNames[i] ?? '#$i').join(' / '),
                        x.hard ? t('قيد إلزامي', 'hard rule') : (x.severity == 'soft' ? t('تفضيل', 'preference') : t('تنبيه', 'warning')),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: orgText(context, size: 12, color: c.textMedium),
                    ),
                  ]),
                ),
              ]),
              RankedActions(actions: x.actions, onAccept: onAccept == null ? null : (a) => onAccept!(x, a), busy: busy.contains(x.key)),
            ]),
          ),
        ),
      if (report.items.length > limit)
        Text(t('+${report.items.length - limit} تعارضاً آخر', '+${report.items.length - limit} more conflicts'), style: orgText(context, size: 12, color: c.textLight)),
    ]);
  }
}
