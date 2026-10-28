// lib/features/org/org_member_today.dart — "Today" for an organization member (home in Organization mode).
//
//   GET /api/v1/org/public/schedule/me?org_id=   published timetables of the member: weekly `items`
//   ({slot_id, day, start_time, end_time, course, title, room, teacher, kind, can_switch}), dated `extras`,
//   `exam_pauses` and `changes` (one-date changes: substitute · online / offline · cancelled, org_member_changes).
//   A session's own teacher / assistant taps it to hold today's occurrence online (students are told and answer).
//
// A published exam window with pause_weekly suspends the term's weekly classes: the weekly sessions of a timetable
// whose exam pause covers today are left out (examPauseOn), extras dated today still count.
// Pure (unit-tested): orgTodaySessions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';

import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart' show asInt, asMapList;
import 'org_member_changes.dart';
import 'org_member_pages.dart' show OrgTimetableScreen;
import 'org_my_exams.dart' show appToday, examPauseBanner, examPauseOn, examPausesOf;
import 'org_providers.dart' show orgBase;

const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's sessions of [timetables] (`/schedule/me` items) on calendar day [today]: weekly slots of today's weekday
/// unless an exam window pauses that timetable today, plus extras dated today — sorted by start time.
/// Each result carries `_extra: true` when it is a dated extra session.
List<Map<String, dynamic>> orgTodaySessions(List<Map<String, dynamic>> timetables, DateTime today) {
  final day = _days[today.weekday - 1];
  final iso = _iso(today);
  final out = <Map<String, dynamic>>[
    for (final s in timetables) ...[
      if (examPauseOn(today, examPausesOf(s)) == null) ...asMapList(s['items']).where((x) => x['day'] == day),
      for (final e in asMapList(s['extras']))
        if ('${e['date'] ?? ''}'.startsWith(iso)) {...e, '_extra': true},
    ],
  ];
  out.sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
  return out;
}

/// Bumped by the hosts' pull-to-refresh (student / teacher home, member dashboard): every [OrgTodayAgenda] reloads.
final ValueNotifier<int> orgTodayEpoch = ValueNotifier(0);

class OrgTodayAgenda extends StatefulWidget {
  const OrgTodayAgenda({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgTodayAgenda> createState() => _OrgTodayAgendaState();
}

class _OrgTodayAgendaState extends State<OrgTodayAgenda> {
  List<Map<String, dynamic>> _timetables = const [];
  bool _loading = true;
  int? _busy; // the change with a request in flight

  Future<void> _respond(OccurrenceChange x, String decision) async {
    setState(() => _busy = x.id);
    if (await respondToChange(x.id, decision)) await _load();
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _undo(OccurrenceChange x) async {
    setState(() => _busy = x.id);
    if (await undoChange(widget.orgId, x.id)) await _load();
    if (mounted) setState(() => _busy = null);
  }

  /// The session's staff: hold today's occurrence online (asks the link) or take it back in person.
  Future<void> _switch(Map<String, dynamic> x, OccurrenceChange? change, DateTime today) async {
    final online = await askSessionMode(context, title: '${x['course'] ?? ''}', date: today, onlineNow: change?.online == true);
    if (online == null || !mounted) return;
    if (await switchSessionMode(context, orgId: widget.orgId, slotId: asInt(x['slot_id']), date: today, online: online)) await _load();
  }

  @override
  void initState() {
    super.initState();
    orgTodayEpoch.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    orgTodayEpoch.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('$orgBase/public/schedule/me', queryParams: {'org_id': widget.orgId});
      if (r is Map) _timetables = asMapList(r['items']);
    } catch (_) {
      // offline / old server: an empty day, never an error wall on the home
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = appToday();
    final rows = orgTodaySessions(_timetables, today);
    final changesToday = orgChangesOn(_timetables, today);
    final upcoming = orgUpcomingChanges(_timetables).take(3).toList();
    final now = homeNow();
    final nowMin = now.hour * 60 + now.minute;
    final pauses = {for (final s in _timetables) for (final p in examPausesOf(s)) '${p['exam_schedule_id']}': p}.values.toList();
    void openWeek() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgTimetableScreen()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle('home_today'.tr,
          count: rows.length, actionLabel: 'home_full_timetable'.tr, onAction: openWeek, padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 10)),
      if (pauses.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: examPauseBanner(context, pauses, padding: EdgeInsets.zero)),
      for (final x in upcoming)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OccurrenceCard(
            change: x,
            busy: _busy == x.id,
            onRespond: x.canRespond ? (d) => _respond(x, d) : null,
            onUndo: x.canEdit ? () => _undo(x) : null,
            onOpenLink: x.onlineUrl == null ? null : () => launchUrl(Uri.parse(x.onlineUrl!), mode: LaunchMode.externalApplication),
          ),
        ),
      HomeAgenda(
        loading: _loading,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        nowMin: nowMin,
        emptyTitle: 'home_no_classes_today'.tr,
        emptyMessage: 'home_no_classes_hint'.tr,
        emptyActionLabel: 'home_full_timetable'.tr,
        onEmptyAction: openWeek,
        items: [
          for (final x in rows)
            HomeAgendaItem(
              start: AppTime.clock(x['start_time']?.toString()),
              end: AppTime.clock(x['end_time']?.toString()),
              startMin: homeClockMinutes(x['start_time']?.toString()),
              endMin: homeClockMinutes(x['end_time']?.toString()),
              live: (homeClockMinutes(x['start_time']?.toString()) ?? 1 << 20) <= nowMin &&
                  nowMin < (homeClockMinutes(x['end_time']?.toString()) ?? -1),
              title: '${x['title'] ?? x['course'] ?? ''}',
              subtitle: [
                if (x['title'] != null && x['course'] != null) '${x['course']}',
                if (x['room'] != null) '${x['room']}',
                if (x['teacher'] != null) '${x['teacher']}',
              ].join(' · '),
              tag: changesToday[asInt(x['slot_id'])]?.label ?? (x['_extra'] == true ? 'home_extra_session'.tr : (x['kind'] == 'lab' ? 'home_lab'.tr : null)),
              tone: changesToday[asInt(x['slot_id'])] != null ? c.primary : (x['kind'] == 'lab' ? c.purple : null),
              onTap: x['can_switch'] == true && x['_extra'] != true ? () => _switch(x, changesToday[asInt(x['slot_id'])], today) : openWeek,
            ),
        ],
      ),
    ]);
  }
}
