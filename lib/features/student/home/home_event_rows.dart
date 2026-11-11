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
//   StudentCourseTiles(courses:)        the same courses on a phone: cover tiles in one horizontal row (D-631)
//
// Plain values only (layout-tested in test/ui/student_home_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart' show OrgTimetableScreen;
import 'package:flutter_education_app/features/org/org_my_exams.dart' show openMyExams;
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/course/course_list_card.dart' show CourseCardShape, CourseListCard, CourseProgressFooter;
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
    // gold is kept for streaks and achievements (system.md §2): a meeting is a quiet ink tag
    tone: switch (e.source) {
      'exam' => c.danger,
      'meeting' => c.textMedium,
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
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: AnimatedSize(
          duration: AppMotion.of(context).base,
          curve: AppEase.out,
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
        'meeting' => c.textMedium,
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
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
            child: Row(children: [
              SizedBox(
                width: AppTouch.primary + AppSpace.xs,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(day, maxLines: 1, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(time, maxLines: 1, style: AppType.meta(context))),
                ]),
              ),
              SizedBox(
                width: AppSpace.md,
                child: Center(
                    child: Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: tone, shape: BoxShape.circle))),
              ),
              AppSpace.gapXs,
              Expanded(
                child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              ),
              if (tag != null) ...[
                AppSpace.gapXs,
                // a long tag never squeezes the title out
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppTouch.min * 2 + AppSpace.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(tag,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, color: appInk(context, tone))),
                  ),
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

/// Each course's latest event that already ended (declined / cancelled ones left out): the home's rows hold today's
/// past classes too. Pure.
Map<int, CalEvent> homeCourseLastEvents(List<CalEvent> events, [DateTime? nowUtc]) {
  final now = nowUtc ?? DateTime.now().toUtc();
  final out = <int, CalEvent>{};
  for (final e in [...events]..sort((a, b) => b.end.compareTo(a.end))) {
    final id = e.courseId;
    if (id == null || e.declined || e.cancelled || e.end.isAfter(now)) continue;
    out.putIfAbsent(id, () => e);
  }
  return out;
}

/// "Next: lecture · when", "Today's class ended · time", or "no lecture scheduled yet". [event] is the course's next
/// calendar event (a live session of today, …): it wins when it comes before the next recorded lecture (M6).
/// [last] is its latest class that already ended: with nothing coming, the card says so rather than "no lecture
/// scheduled" next to a Today list that shows the course's classes (M6).
String homeNextLectureLine(MeCourseProgress x, {CalEvent? event, CalEvent? last, DateTime? nowUtc}) {
  final n = x.nextLecture;
  final lectureAt = n?.scheduledAt;
  if (event != null && (n == null || lectureAt == null || event.start.isBefore(lectureAt))) {
    final now = nowUtc ?? DateTime.now().toUtc();
    if (!event.start.isAfter(now)) return 'home_course_live_now'.tr.replaceAll('{n}', event.title);
    return 'home_next_lecture'.tr.replaceAll('{n}', event.title) + ' · ${AppTime.dateTime(event.start)}';
  }
  if (n == null) {
    if (last != null) return 'home_course_ended_today'.tr.replaceAll('{t}', AppTime.time(last.end));
    return 'home_no_next_lecture'.tr;
  }
  final when = lectureAt == null ? '' : ' · ${AppTime.dateTime(lectureAt)}';
  return 'home_next_lecture'.tr.replaceAll('{n}', n.name) + when;
}

/// "My courses" summarized in one card: the three courses that matter now (homeCourseFocus), each with its next
/// lecture and progress — the count sits in the section title, the totals on the courses tab; tap → the course,
/// the foot → the courses tab.
class StudentCourseSummary extends StatelessWidget {
  const StudentCourseSummary({super.key, required this.courses, this.events = const [], this.onOpen, this.onShowAll, this.featuredId});
  final List<MeCourseProgress> courses;

  /// The course the "Continue learning" block above already shows (StudentContinueBlock): left out of the lines,
  /// still counted in "All n courses".
  final int? featuredId;

  /// The home's today + upcoming rows: a course's next class when it has no recorded lecture coming.
  final List<CalEvent> events;
  final ValueChanged<int>? onOpen;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final top = homeCourseFocus(courses, events: events).where((x) => x.courseId != featuredId).take(3).toList();
    final shown = top.length + (featuredId != null && courses.any((x) => x.courseId == featuredId) ? 1 : 0);
    final next = homeCourseNextEvents(events);
    final last = homeCourseLastEvents(events);
    return HomeCourseSummary(
      figures: const [],
      lines: [
        for (final x in top)
          HomeCourseLine(
            title: x.name(AppConfig.lang),
            subtitle: homeNextLectureLine(x, event: next[x.courseId], last: last[x.courseId]),
            imageUrl: x.imageUrl,
            progress: x.progress,
            trailing: '${x.progress.round()}%',
            onTap: onOpen == null ? null : () => onOpen!(x.courseId),
          ),
      ],
      moreLabel: courses.length > shown ? 'home_courses_all'.tr.replaceAll('{n}', '${courses.length}') : null,
      onMore: onShowAll,
    );
  }
}

/// "My courses" on a phone (D-631): the same courses as [StudentCourseSummary] (all of them, the focus order, the
/// featured one left out) as cover tiles in one horizontal row, each with its next lecture and its progress.
class StudentCourseTiles extends StatelessWidget {
  const StudentCourseTiles({super.key, required this.courses, this.events = const [], this.onOpen, this.featuredId});

  final List<MeCourseProgress> courses;
  final List<CalEvent> events;
  final ValueChanged<int>? onOpen;
  final int? featuredId;

  /// One tile's width: a second tile always peeks in at the end.
  static const double tileWidth = AppDashSize.courseTile;

  @override
  Widget build(BuildContext context) {
    final list = homeCourseFocus(courses, events: events).where((x) => x.courseId != featuredId).toList();
    final next = homeCourseNextEvents(events);
    final last = homeCourseLastEvents(events);
    return SizedBox(
      height: CourseListCard.tileHeight(context, tileWidth),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final x = list[i];
          return SizedBox(
            width: tileWidth,
            child: CourseListCard(
              shape: CourseCardShape.tile,
              title: x.name(AppConfig.lang),
              imageUrl: x.imageUrl ?? '',
              meta: [homeNextLectureLine(x, event: next[x.courseId], last: last[x.courseId])],
              footer: CourseProgressFooter(progress: x.progress.round()),
              onTap: onOpen == null ? null : () => onOpen!(x.courseId),
            ),
          );
        },
      ),
    );
  }
}
