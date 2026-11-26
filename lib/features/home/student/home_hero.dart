// lib/features/home/student/home_hero.dart — the student home's redesign head (StuHome?screen=home, phase 2 S-A).
//
//   StudentHomeTopBar   phone only: the dark top band (the mark, "Home", the shell's icons as glass chips)
//   StudentHomeHero     the area hero: the greeting kicker, ONE line that says what matters now (a live class, the
//                       course to pick up, or a free day) with its squiggled word; on a wide window the day's line,
//                       the four figures as glass stats and a countdown to the next class
//   StudentContinueCard "Pick up where you left off": up to three courses as tiles (subject glyph, the next lesson,
//                       a progress ring) and a row of small figures (courses · progress · finished)
//   studentHeroLine()   the hero's line from plain values (tested)
//
// Plain values only: the screen (home_screen.dart) feeds them from /me/home (one call; no request here).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_hero.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppCard;
import 'package:flutter_education_app/design/app_progress.dart';
import 'package:flutter_education_app/design/app_tiles.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeBar;
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/courses/course_list_card.dart' show courseSubjectIcon, courseSubjectKeyOf;

/// The hero's line and its one squiggled word.
typedef StudentHeroLine = ({String title, String? squiggle});

/// What the hero says: a live class first, then the course to pick up, else a free day.
StudentHeroLine studentHeroLine({List<MeLiveRoom> live = const [], MeCourseProgress? featured, bool guest = false}) {
  if (guest) return (title: 'sa_home_guest_title'.tr, squiggle: 'sa_home_guest_squiggle'.tr);
  final room = live.where((r) => !r.isMeeting).firstOrNull ?? live.firstOrNull;
  if (room != null) {
    final subject = room.title.trim().isEmpty ? 'sa_home_class'.tr : room.title.trim();
    return (title: 'sa_home_live_title'.tr.replaceAll('{subject}', subject), squiggle: 'sa_home_live_squiggle'.tr);
  }
  if (featured != null) {
    final name = AppConfig.lang == 'ar' ? featured.nameAr : featured.nameEn;
    return (title: 'sa_home_featured_title'.tr.replaceAll('{course}', name), squiggle: 'sa_home_featured_squiggle'.tr);
  }
  return (title: 'sa_home_free_title'.tr, squiggle: 'sa_home_free_squiggle'.tr);
}

/// "Good morning, Faisal" / "Good evening, Faisal" by the viewer's wall clock.
String studentGreetingKicker(String name, [DateTime? nowUtc]) {
  final h = AppTime.toZone(nowUtc ?? DateTime.now().toUtc()).hour;
  final key = h >= 4 && h < 12 ? 'sa_greet_morning' : 'sa_greet_evening';
  return key.tr.replaceAll('{name}', name);
}

/// The phone's top band: the mark and "Home" at the start, the shell's icons (glass) at the end.
class StudentHomeTopBar extends StatelessWidget {
  const StudentHomeTopBar({super.key, this.actions = const [], this.title});

  final List<Widget> actions;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.kit.topBar,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDashSize.topBarPhone),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
          child: Row(children: [
            ExcludeSemantics(
              child: Image.asset('assets/images/logo_mark.png', width: AppIconSize.xl, height: AppIconSize.xl),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title ?? 'sa_home_top_title'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.section(context).copyWith(color: c.onHero),
                ),
              ),
            ),
            ChromeBar(
              child: Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The student home's hero (see the file header).
class StudentHomeHero extends StatelessWidget {
  const StudentHomeHero({
    super.key,
    required this.name,
    required this.line,
    this.home,
    this.daySummary,
    this.now,
    this.guest = false,
    this.onTab,
  });

  final String name;
  final StudentHeroLine line;
  final MeHome? home;

  /// The day in one line (wide only).
  final String? daySummary;
  final DateTime? now;
  final bool guest;
  final ValueChanged<String>? onTab;

  /// The next class or exam within two days (a countdown on a wide window).
  static CalEvent? nextEvent(MeHome? home, DateTime nowUtc) {
    if (home == null) return null;
    final soon = [...home.today, ...home.upcoming]
        .where((e) => !e.declined && e.start.isAfter(nowUtc) && e.start.difference(nowUtc) < const Duration(days: 2))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return soon.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final nowUtc = now ?? DateTime.now().toUtc();
    final h = home;
    final stats = <AppHeroStat>[];
    if (h != null && !guest) {
      final cp = h.coursesProgress;
      final avg = cp.isEmpty ? 0 : (cp.fold<double>(0, (s, x) => s + x.progress) / cp.length).round();
      stats.addAll([
        if (_on('my_courses'))
          AppHeroStat(
              icon: Icons.auto_stories_rounded,
              value: '${cp.length}',
              label: 'sa_stat_courses'.tr,
              onTap: onTab == null ? null : () => onTab!('my_courses')),
        if (_on('my_schedule'))
          AppHeroStat(
              icon: Icons.event_note_rounded,
              value: '${h.today.where((e) => !e.declined).length}',
              label: 'sa_stat_today'.tr,
              onTap: onTab == null ? null : () => onTab!('my_schedule')),
        if (_on('analysis'))
          AppHeroStat(
              icon: Icons.trending_up_rounded,
              value: '$avg%',
              label: 'sa_stat_progress'.tr,
              onTap: onTab == null ? null : () => onTab!('analysis')),
        if (_on('my_courses'))
          AppHeroStat(
              icon: Icons.emoji_events_rounded,
              value: '${cp.where((x) => x.progress >= 100).length}',
              label: 'sa_stat_done'.tr),
      ]);
    }
    final next = guest ? null : nextEvent(h, nowUtc);
    return AppHero(
      kicker: guest ? 'sa_greet_guest'.tr : studentGreetingKicker(name, nowUtc),
      title: line.title,
      squiggle: line.squiggle,
      subtitle: daySummary,
      stats: stats,
      trailing: next == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('sa_home_next_in'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: context.colors.onHeroMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.xs),
              AppCountdown(until: next.start, onHero: true),
            ]),
    );
  }

  static bool _on(String tab) => !AppConfig.disableList.contains('student_tab_$tab');
}

/// "Pick up where you left off": up to three courses and the small figures under them.
class StudentContinueCard extends StatelessWidget {
  const StudentContinueCard({
    super.key,
    required this.courses,
    this.lineFor,
    this.onOpen,
    this.onShowAll,
    this.streakDays,
  });

  final List<MeCourseProgress> courses;

  /// The next lesson line of a course (homeNextLectureLine); null = its next lecture's name.
  final String Function(MeCourseProgress x)? lineFor;
  final ValueChanged<int>? onOpen;
  final VoidCallback? onShowAll;

  /// Days in a row, when the payload has them.
  final int? streakDays;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    // the ones that are not finished first, the most advanced of them on top (the course to pick up)
    final list = [...courses]..sort((a, b) {
        final da = a.progress >= 100 ? 1 : 0, db = b.progress >= 100 ? 1 : 0;
        if (da != db) return da - db;
        return b.progress.compareTo(a.progress);
      });
    final shown = list.take(3).toList();
    final avg = courses.isEmpty ? 0 : (courses.fold<double>(0, (s, x) => s + x.progress) / courses.length).round();
    final done = courses.where((x) => x.progress >= 100).length;
    final link = onShowAll == null
        ? null
        : TextButton(
            onPressed: onShowAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(AppTouch.min, AppTouch.min),
              foregroundColor: AppAreaScope.of(context).ink,
            ),
            child: Text('sa_home_all_courses'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: AppAreaScope.of(context).ink)),
          );
    return AppCard(
      child: LayoutBuilder(builder: (context, box) {
        final grid = box.maxWidth >= 640;
        final tiles = [
          for (final x in shown)
            _CourseTile(
              course: x,
              line: lineFor?.call(x) ?? x.nextLecture?.name ?? '',
              title: ar ? x.nameAr : x.nameEn,
              onTap: onOpen == null ? null : () => onOpen!(x.courseId),
            ),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          // the head: the title and "All my courses" (the link gives way first on a narrow card)
          Row(children: [
            Expanded(
              child: Text('sa_home_cont_card'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
            if (link != null) ...[const SizedBox(width: AppSpace.xs), Flexible(child: link)],
          ]),
          const SizedBox(height: AppSpace.sm),
          if (grid)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                Expanded(child: i < tiles.length ? tiles[i] : const SizedBox.shrink()),
              ],
            ])
          else
            for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), tiles[i]],
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppStatusBadge(
              label: countText(courses.length,
                  ar1: 'دورة واحدة', ar2: 'دورتان', arFew: '{n} دورات', arMany: '{n} دورة', en1: '1 course', en: '{n} courses'),
              tone: AppTone.info,
            ),
            AppStatusBadge(label: 'sa_home_chip_progress'.tr.replaceAll('{n}', '$avg'), accent: AppAccent.sun),
            if (done > 0) AppStatusBadge(label: 'sa_home_chip_done'.tr.replaceAll('{n}', '$done'), tone: AppTone.success),
            if (streakDays != null && streakDays! > 0)
              AppStatusBadge(label: 'sa_home_chip_streak'.tr.replaceAll('{n}', '$streakDays'), accent: AppAccent.lime),
          ]),
          if (c.isDark) const SizedBox.shrink(),
        ]);
      }),
    );
  }
}

/// One course of the continue card: the subject glyph, the name, the next lesson in the subject's ink, a ring.
class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course, required this.title, required this.line, this.onTap});

  final MeCourseProgress course;
  final String title;
  final String line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final key = courseSubjectKeyOf(title);
    final s = context.colors.kit.subject(key);
    return AppTile(
      icon: courseSubjectIcon(key),
      tone: s.tone,
      title: title,
      subtitle: line.isEmpty ? null : line,
      trailing: AppProgressRing(value: course.progress / 100, tone: s.tone),
      onTap: onTap,
    );
  }
}

/// The guest's "Sign in" on the phone's top band: a glass pill.
class StudentGuestSignIn extends StatelessWidget {
  const StudentGuestSignIn({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(AppTouch.min, AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          backgroundColor: c.heroGlass,
          foregroundColor: c.onHero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline),
          ),
        ),
        child: Text('sa_guest_signin'.tr, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
