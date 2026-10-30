// lib/features/student/home/home_event_rows.dart — the home's event pieces, shared by the student home and the
// organization member home (both draw the SAME /me/home events):
//
//   openHomeEvent(context, e, inOrg:)   where a tapped event goes (meeting → calendar · course session → the course ·
//                                       exam → my exams · timetable slot → the calendar, or the member's timetable
//                                       in Organization mode)
//   homeAgendaItemOf(context, e, now)   a CalEvent as a HomeAgenda row (times through AppTime, live while running)
//   homeEventTag(e) · homeDuration(min) the tag of an event (lab · exam · meeting · online) · "1 h 20 min"
//   UpcomingList(events:)               "This week": one line per event (day + time column), 3 + "Show all"
//   homeDaySummaryOf(today, now)        a folded "Today" section's quiet line
//   homeFreeDaySummary(empty, upcoming) an EMPTY "Today" section's line: "No classes today · Next: … · Thu 30"
//
// There is no "next up" hero card any more: it repeated the first row of "Today". What only it said (ends in
// 50 min · the room) is the second line of that row now (HomeAgenda: homeAgendaNote, the item's place).
//   StudentCourseSummary(courses:)      "My courses" in one card: the 3 that matter now (homeCourseFocus)
//
// Plain values only (layout-tested in test/ui/student_home_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart' show OrgTimetableScreen;
import 'package:flutter_education_app/features/org/org_my_exams.dart' show openMyExams;
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';

/// Where an event of the home goes when tapped. [inOrg]: a timetable slot opens the member's own timetable
/// (changes · hold online) instead of the calendar.
void openHomeEvent(BuildContext context, CalEvent e, {bool inOrg = false}) {
  final nav = Navigator.of(context);
  switch (e.source) {
    case 'meeting':
      nav.pushNamed('/calendar', arguments: {'meeting_id': e.meetingId, 'org_id': ?e.orgId});
    case 'course_session':
      if (e.courseId != null) {
        AppNavigator.openCourse(e.courseId!);
      } else {
        nav.pushNamed('/calendar');
      }
    case 'exam':
      openMyExams(context, orgId: e.orgId);
    default: // timetable · extra
      if (inOrg && e.orgId != null) {
        nav.push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: e.orgId)));
      } else {
        nav.pushNamed('/calendar', arguments: {'org_id': ?e.orgId});
      }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pieces (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// The tag of an event (lab · exam · meeting · online), null for a plain lecture.
String? homeEventTag(CalEvent e) => switch (e.source) {
      'exam' => 'home_exam'.tr,
      'meeting' => 'home_meeting'.tr,
      'extra' => 'home_extra_session'.tr,
      _ => e.kind == 'lab' ? 'home_lab'.tr : (e.mode == 'online' ? 'home_online'.tr : null),
    };

/// A calendar event as an agenda row (times through AppTime; live while running at [nowUtc]).
HomeAgendaItem homeAgendaItemOf(BuildContext context, CalEvent e, DateTime nowUtc, {VoidCallback? onTap}) {
  final c = context.colors;
  final ws = e.wallStart, we = e.wallEnd;
  return HomeAgendaItem(
    start: AppTime.time(e.start),
    end: AppTime.time(e.end),
    startMin: ws.hour * 60 + ws.minute,
    endMin: we.hour * 60 + we.minute,
    live: !e.start.isAfter(nowUtc) && e.end.isAfter(nowUtc),
    title: e.title,
    subtitle: [
      if (e.subtitle != null && e.subtitle!.isNotEmpty) e.subtitle!,
      if (e.location != null && e.location!.isNotEmpty) e.location!,
      if (e.orgName != null && e.orgName!.isNotEmpty) e.orgName!,
    ].join(' · '),
    place: e.location,
    tag: homeEventTag(e),
    tone: switch (e.source) {
      'exam' => c.danger,
      'meeting' => c.accent2,
      _ => e.kind == 'lab' ? c.purple : null,
    },
    onTap: onTap,
  );
}

/// A folded "Today" section's quiet line: "4 sessions today · 1 live now" / "… · next at 1:00 PM".
String homeDaySummaryOf(List<CalEvent> today, DateTime nowUtc) {
  final live = today.where((e) => !e.start.isAfter(nowUtc) && e.end.isAfter(nowUtc)).length;
  final next = today.where((e) => e.start.isAfter(nowUtc)).firstOrNull;
  return [
    today.length == 1 ? 'home_sum_sessions_one'.tr : 'home_sum_sessions'.tr.replaceAll('{n}', '${today.length}'),
    if (live > 0) 'home_sum_live'.tr.replaceAll('{n}', '$live'),
    if (live == 0 && next != null) 'home_sum_next'.tr.replaceAll('{t}', AppTime.time(next.start)),
  ].join(' · ');
}

/// An empty "Today" section's line (it starts folded): "No classes today · Next: Operating systems · Thu 30", or
/// only [empty] (the role's own "nothing today") when nothing is coming.
String homeFreeDaySummary(String empty, CalEvent? upcoming) {
  if (upcoming == null) return empty;
  final next = 'home_next_on'.tr.replaceAll('{t}', upcoming.title).replaceAll('{d}', AppTime.date(upcoming.start, pattern: 'EEE d'));
  return '$empty · $next';
}

String homeDuration(int minutes) => homeDurationText(minutes);

/// "This week": one compact line per event — the day and time in a small column, a dot in the event's tone, the
/// title, the tag — the first [maxItems] and "Show all (n)".
class UpcomingList extends StatefulWidget {
  const UpcomingList({super.key, required this.events, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 20), this.maxItems = 3});
  final List<CalEvent> events;
  final ValueChanged<CalEvent>? onTap;
  final EdgeInsetsGeometry padding;
  final int maxItems;

  @override
  State<UpcomingList> createState() => _UpcomingListState();
}

class _UpcomingListState extends State<UpcomingList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final events = widget.events;
    final more = events.length > widget.maxItems;
    final shown = _all || !more ? events : events.take(widget.maxItems).toList();
    return Padding(
      padding: widget.padding,
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AnimatedSize(
          duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topCenter,
          child: Column(children: [
            for (final e in shown) _UpcomingLine(e: e, tone: _tone(c, e), onTap: widget.onTap == null ? null : () => widget.onTap!(e)),
            if (more) HomeShowAllRow(expanded: _all, count: events.length, onTap: () => setState(() => _all = !_all)),
          ]),
        ),
      ),
    );
  }

  static Color _tone(ThemeConfigProvider c, CalEvent e) => switch (e.source) {
        'exam' => c.danger,
        'meeting' => c.accent2,
        _ => e.kind == 'lab' ? c.purple : c.primary,
      };
}

class _UpcomingLine extends StatelessWidget {
  const _UpcomingLine({required this.e, required this.tone, this.onTap});
  final CalEvent e;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tag = homeEventTag(e);
    final day = AppTime.date(e.start, pattern: 'EEE d');
    final time = AppTime.time(e.start);
    return Semantics(
      button: onTap != null,
      excludeSemantics: true,
      label: [day, '$time – ${AppTime.time(e.end)}', e.title, ?tag, if (e.orgName != null && e.orgName!.isNotEmpty) e.orgName!].join(', '),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(day, maxLines: 1, style: appText(12.5, w: FontWeight.w600, c: c.textDark))),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(time, maxLines: 1, style: appText(11.5, c: c.textMedium))),
                ]),
              ),
              SizedBox(
                width: 16,
                child: Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.3)),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 112), // a long tag never squeezes the title out
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(tag,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: appInk(context, tone))),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The order the home shows courses in: the soonest scheduled next lecture first, then the furthest along that
/// is not finished, finished courses last. [events] (the home's today / upcoming rows) count as a course's next
/// class too: a course with 3 live sessions today is not "no lecture scheduled".
List<MeCourseProgress> homeCourseFocus(List<MeCourseProgress> all, {List<CalEvent> events = const [], DateTime? nowUtc}) {
  final next = homeCourseNextEvents(events, nowUtc);
  DateTime? at(MeCourseProgress x) {
    final a = x.nextLecture?.scheduledAt, b = next[x.courseId]?.start;
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  int rank(MeCourseProgress x) => x.progress >= 100 ? 2 : (at(x) != null ? 0 : 1);
  return [...all]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (rank(a) == 0) return at(a)!.compareTo(at(b)!);
      return b.progress.compareTo(a.progress);
    });
}

/// Each course's first event that has not ended (declined / cancelled ones left out). Pure.
Map<int, CalEvent> homeCourseNextEvents(List<CalEvent> events, [DateTime? nowUtc]) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final out = <int, CalEvent>{};
  for (final e in [...events]..sort((a, b) => a.start.compareTo(b.start))) {
    final id = e.courseId;
    if (id == null || e.declined || e.cancelled || !e.end.isAfter(now)) continue;
    out.putIfAbsent(id, () => e);
  }
  return out;
}

/// "Next: lecture · when", or "no lecture scheduled yet". [event] is the course's next calendar event (a live
/// session of today, …): it wins when it comes before the next recorded lecture (M6).
String homeNextLectureLine(MeCourseProgress x, {CalEvent? event, DateTime? nowUtc}) {
  final n = x.nextLecture;
  final lectureAt = n?.scheduledAt;
  if (event != null && (n == null || lectureAt == null || event.start.isBefore(lectureAt))) {
    final now = nowUtc ?? DateTime.now().toUtc();
    if (!event.start.isAfter(now)) return 'home_course_live_now'.tr.replaceAll('{n}', event.title);
    return 'home_next_lecture'.tr.replaceAll('{n}', event.title) + ' · ${AppTime.dateTime(event.start)}';
  }
  if (n == null) return 'home_no_next_lecture'.tr;
  final when = lectureAt == null ? '' : ' · ${AppTime.dateTime(lectureAt)}';
  return 'home_next_lecture'.tr.replaceAll('{n}', n.name) + when;
}

/// "My courses" summarized in one card: the three courses that matter now (homeCourseFocus), each with its next
/// lecture and progress — the count sits in the section title, the totals on the courses tab; tap → the course,
/// the foot → the courses tab.
class StudentCourseSummary extends StatelessWidget {
  const StudentCourseSummary({super.key, required this.courses, this.events = const [], this.onOpen, this.onShowAll});
  final List<MeCourseProgress> courses;

  /// The home's today + upcoming rows: a course's next class when it has no recorded lecture coming.
  final List<CalEvent> events;
  final ValueChanged<int>? onOpen;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final top = homeCourseFocus(courses, events: events).take(3).toList();
    final next = homeCourseNextEvents(events);
    return HomeCourseSummary(
      figures: const [],
      lines: [
        for (final x in top)
          HomeCourseLine(
            title: x.name(AppConfig.lang),
            subtitle: homeNextLectureLine(x, event: next[x.courseId]),
            imageUrl: x.imageUrl,
            progress: x.progress,
            trailing: '${x.progress.round()}%',
            onTap: onOpen == null ? null : () => onOpen!(x.courseId),
          ),
      ],
      moreLabel: courses.length > top.length ? 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}') : null,
      onMore: onShowAll,
    );
  }
}
