// lib/features/student/home/home_event_rows.dart — the home's event pieces, shared by the student home and the
// organization member home (both draw the SAME /me/home events):
//
//   openHomeEvent(context, e, inOrg:)   where a tapped event goes (meeting → calendar · course session → the course ·
//                                       exam → my exams · timetable slot → the calendar, or the member's timetable
//                                       in Organization mode)
//   homeAgendaItemOf(context, e, now)   a CalEvent as a HomeAgenda row (times through AppTime, live while running)
//   homeEventTag(e) · homeDuration(min) the tag of an event (lab · exam · meeting · online) · "1 h 20 min"
//   NextUpHero(next:, now:, upcoming:)  the hero: the next event's start time set big, live state, countdown
//   UpcomingList(events:)               "This week": compact rows with the day in a small column
//   CourseProgressList(courses:, now:)  "Continue learning": thin progress bar + the next lecture per course
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
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

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
    tag: homeEventTag(e),
    tone: switch (e.source) {
      'exam' => c.danger,
      'meeting' => c.accent2,
      _ => e.kind == 'lab' ? c.purple : null,
    },
    onTap: onTap,
  );
}

String homeDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return 'home_min'.tr.replaceAll('{n}', '$m');
  return 'home_h_min'.tr.replaceAll('{h}', '$h').replaceAll('{m}', '$m');
}

/// The student's hero: today's next event, its start time set big, live state, countdown. Free day → a calm
/// green card that names the first upcoming day.
class NextUpHero extends StatelessWidget {
  const NextUpHero({super.key, required this.next, required this.now, this.upcoming, this.onTap});
  final MeNextUp? next;
  final CalEvent? upcoming;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = homeOnHero(context);
    final n = next;
    if (n == null) {
      final up = upcoming;
      return HomeHeroCard(
        gradient: c.successGradient,
        glow: c.success,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HomeHeroTag('home_today'.tr, icon: Icons.wb_sunny_rounded),
          const SizedBox(height: 14),
          Text('no_sessions_today_title'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(22, w: FontWeight.w900, c: on, h: 1.2)),
          const SizedBox(height: 6),
          Text(
            up == null ? 'check_weekly_schedule'.tr : 'home_next_on'.tr.replaceAll('{d}', AppTime.date(up.start, pattern: 'EEEE d MMM')).replaceAll('{t}', up.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appText(13, c: on.withValues(alpha: 0.9)),
          ),
        ]),
      );
    }
    final e = n.event;
    final mins = n.live ? e.end.difference(now).inMinutes : e.start.difference(now).inMinutes;
    final rel = mins <= 0 ? '' : (n.live ? 'home_ends_in' : 'home_starts_in').tr.replaceAll('{t}', homeDuration(mins));
    final tag = homeEventTag(e);
    return HomeHeroCard(
      gradient: n.live ? c.dangerGradient : c.primaryGradient,
      glow: n.live ? c.danger : c.primary,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HomeHeroTag(n.live ? 'home_live'.tr : (tag ?? 'home_next'.tr), icon: n.live ? Icons.sensors_rounded : Icons.schedule_rounded),
          const SizedBox(width: 8),
          if (rel.isNotEmpty)
            Expanded(
              child: Text(rel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: appText(12.5, w: FontWeight.w700, c: on.withValues(alpha: 0.9))),
            ),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(AppTime.time(e.start), maxLines: 1, style: appText(40, w: FontWeight.w900, c: on, h: 1.05)),
        ),
        const SizedBox(height: 6),
        Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(17, w: FontWeight.w800, c: on, h: 1.25)),
        const SizedBox(height: 4),
        Text(
          [
            '${'home_until'.tr} ${AppTime.time(e.end)}',
            if (e.location != null && e.location!.isNotEmpty) e.location!,
            if (e.orgName != null && e.orgName!.isNotEmpty) e.orgName!,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appText(12.5, c: on.withValues(alpha: 0.85)),
        ),
      ]),
    );
  }
}

/// "This week": compact rows, the day in a small column, grouped visually by day.
class UpcomingList extends StatelessWidget {
  const UpcomingList({super.key, required this.events, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<CalEvent> events;
  final ValueChanged<CalEvent>? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String? lastDay;
    return Padding(
      padding: padding,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(children: [
          for (final e in events)
            Builder(builder: (context) {
              final day = '${e.wallStart.year}-${e.wallStart.month}-${e.wallStart.day}';
              final first = day != lastDay;
              lastDay = day;
              final tone = switch (e.source) {
                'exam' => c.danger,
                'meeting' => c.accent2,
                _ => e.kind == 'lab' ? c.purple : c.primary,
              };
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap == null ? null : () => onTap!(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 44,
                      child: first
                          ? Column(children: [
                              Text(AppTime.date(e.start, pattern: 'EEE'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w700, c: c.textLight)),
                              Text('${e.wallStart.day}', maxLines: 1, style: appText(18, w: FontWeight.w900, c: c.textDark, h: 1.1)),
                            ])
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 3, height: 36, margin: const EdgeInsets.only(top: 2), decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '${AppTime.time(e.start)} – ${AppTime.time(e.end)}',
                            if (homeEventTag(e) != null) homeEventTag(e)!,
                            if (e.orgName != null && e.orgName!.isNotEmpty) e.orgName!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(11.5, c: c.textMedium),
                        ),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

/// "Continue learning": a thin progress bar per course and the next lecture; tap → the course.
class CourseProgressList extends StatelessWidget {
  const CourseProgressList({super.key, required this.courses, required this.now, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 20)});
  final List<MeCourseProgress> courses;
  final DateTime now;
  final ValueChanged<int>? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding,
      child: Column(children: [
        for (final x in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              onTap: onTap == null ? null : () => onTap!(x.courseId),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: x.imageUrl != null && x.imageUrl!.startsWith('http')
                        ? AppNetworkImage(url: x.imageUrl!, width: 56, height: 56)
                        : ColoredBox(color: c.primaryTint, child: Icon(Icons.menu_book_rounded, color: c.primary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.name(AppConfig.lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: AppProgressBar(value: x.progress, height: 5, color: appScoreColor(context, x.progress))),
                      const SizedBox(width: 8),
                      Text('${x.progress.round()}%', style: appText(11.5, w: FontWeight.w800, c: c.textMedium)),
                    ]),
                    const SizedBox(height: 6),
                    Text(_nextLine(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
                  ]),
                ),
                const SizedBox(width: 6),
                Icon(Icons.play_circle_fill_rounded, color: c.primary, size: 26),
              ]),
            ),
          ),
      ]),
    );
  }

  String _nextLine(MeCourseProgress x) {
    final n = x.nextLecture;
    if (n == null) return 'home_no_next_lecture'.tr;
    final when = n.scheduledAt == null ? '' : ' · ${AppTime.dateTime(n.scheduledAt!)}';
    return 'home_next_lecture'.tr.replaceAll('{n}', n.name) + when;
  }
}
