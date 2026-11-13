// lib/features/shared/calendar/schedule_parts.dart — the presentational pieces of the one schedule page (D-085).
//
// Plain values in, callbacks out (no provider, no API), so test/ui/schedule_layout_test.dart pumps each one at
// 320×640 and 1400×900, Arabic + English, text ×1.3:
//
//   CalPageTabs         the page's two tabs: Scheduled meetings · Calendar (D-321)
//   CalViewSwitch       Day · Week · Month, a segmented pill (the Calendar tab)
//   CalFilterChips      the kinds (+ organizations) as chips with their counts — phone / tablet
//   CalFilterPanel      the same as a list with colour checks — the desktop sidebar
//   CalMonthPicker      a month of days with event dots, today ring, the selected day / range; mini (sidebar,
//                       phone header) or roomy (the phone's month view)
//   CalWeekStrip        seven day pills with dots (the phone's day view)
//   CalTodayHero        the list's head: today's date, what is left, the next event with Join when it is open
//   CalLiveNowCard      a room open right now: the most prominent row of the list, with Join
//   CalListBar          "Coming up" / "Past and ended" with the action that flips between them
//   CalAgendaList       days → CalAgendaDayCard (date tile + one card per event + the "now" line + exam-window banner), free-day note
//   CalAgendaTile       one event: time column, colour bar, title, meta, tags (live · online · substitute · cancelled
//                       · my answer), inline Join / Accept · Decline / the change's Accept · Reject
//   CalEventSheet       a non-meeting event's details: time, place, people, the one-date change with its answers,
//                       Join / Open course / My exams / My timetable
//   CalUpNextCard · CalInvitesCard   the desktop sidebar's "Up next" and pending invitations
//   CalScheduleSkeleton the loading state of each view (shimmer, never a spinner)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppReveal, AppTilt;

import '../../admin/admin_common.dart' show t;
import 'calendar_models.dart';
import 'schedule_logic.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Small shared bits
// ═════════════════════════════════════════════════════════════════════════════

String calViewLabel(CalView v) => switch (v) {
      CalView.agenda => t('الأجندة', 'Agenda'),
      CalView.day => t('يوم', 'Day'),
      CalView.week => t('أسبوع', 'Week'),
      CalView.month => t('شهر', 'Month'),
    };

/// The views of the Calendar tab (the list is the other tab).
const calGridViews = [CalView.day, CalView.week, CalView.month];

/// "Past and ended" reaches back this many days at a time, up to [calPastMax].
const calPastStep = 14;
const calPastMax = 84;

IconData calViewIcon(CalView v) => switch (v) {
      CalView.agenda => Icons.view_agenda_rounded,
      CalView.day => Icons.view_day_rounded,
      CalView.week => Icons.view_week_rounded,
      CalView.month => Icons.calendar_view_month_rounded,
    };

String _dayTitle(DateTime day, DateTime today) {
  final d = calDay(day).difference(calDay(today)).inDays;
  if (d == 0) return t('اليوم', 'Today');
  if (d == 1) return t('غداً', 'Tomorrow');
  if (d == -1) return t('أمس', 'Yesterday');
  return AppTime.date(AppTime.fromZone(DateTime(day.year, day.month, day.day, 12)), pattern: 'EEEE');
}

String _dayDate(DateTime day, {String pattern = 'd MMMM'}) =>
    AppTime.date(AppTime.fromZone(DateTime(day.year, day.month, day.day, 12)), pattern: pattern);

/// The tint of an event kind on cards: stronger in dark mode, where a light tint would vanish.
Color calTint(ThemeConfigProvider c, Color base, [double light = 0.10]) => base.withValues(alpha: c.isDark ? light * 2.0 : light);

/// A small rounded label: [color] tone, filled when [solid].
class CalTag extends StatelessWidget {
  const CalTag(this.label, this.color, {super.key, this.icon, this.solid = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = solid ? c.onHero : appInk(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: solid ? color : calTint(c, color, 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs - 2, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: ink)),
        ),
      ]),
    );
  }
}

/// THE live mark of the schedule (system brief: live = a danger dot): a still danger dot on a soft ring of its own
/// tint, never a glow or a red slab (a decorative pulse would need syncMotionLoop; a still dot tells the same).
class CalLiveDot extends StatelessWidget {
  const CalLiveDot({super.key, this.size = 8});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size + AppSpace.xxs,
      height: size + AppSpace.xxs,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: calTint(c, c.danger, 0.18), shape: BoxShape.circle),
      child: Container(width: size, height: size, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page's two tabs, view switch
// ═════════════════════════════════════════════════════════════════════════════

class CalPageTabs extends StatelessWidget {
  const CalPageTabs({super.key, required this.index, required this.onChanged, this.invites = 0, this.expand = false});

  /// 0 Scheduled meetings · 1 Calendar.
  final int index;
  final ValueChanged<int> onChanged;

  /// Invitations awaiting an answer: the count on the first tab.
  final int invites;
  final bool expand;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // a phone's two tabs share the row: the long label alone keeps them equal, with room to spare
        final roomy = box.maxWidth >= 440;
        return AppTabs(
          expand: expand,
          index: index,
          onChanged: onChanged,
          items: [
            AppTabItem(t('الاجتماعات المجدولة', 'Scheduled meetings'), icon: roomy ? Icons.event_note_rounded : null, count: roomy && invites > 0 ? invites : null),
            AppTabItem(t('التقويم', 'Calendar'), icon: roomy ? Icons.calendar_month_rounded : null),
          ],
        );
      });
}

class CalViewSwitch extends StatelessWidget {
  const CalViewSwitch({super.key, required this.view, required this.onView, this.views = CalView.values, this.expand = false});
  final CalView view;
  final ValueChanged<CalView> onView;
  final List<CalView> views;

  /// Stretch to the full width (phone) instead of hugging the labels (toolbar).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(CalView v) {
      final on = v == view;
      final child = Semantics(
        button: true,
        selected: on,
        label: calViewLabel(v),
        child: InkWell(
          key: ValueKey('cal.view.${v.name}'),
          borderRadius: AppRadius.chipAll,
          onTap: () => onView(v),
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs - 2),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs - 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.cardBg : c.cardBg.withValues(alpha: 0),
              borderRadius: AppRadius.chipAll,
              border: Border.all(color: on ? c.divider : c.divider.withValues(alpha: 0), width: AppBorder.hairline),
            ),
            child: Text(
              calViewLabel(v),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? c.textDark : c.textMedium),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.xxs - 1),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.chip + AppSpace.xxs - 1),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [for (final v in views) seg(v)]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Filters
// ═════════════════════════════════════════════════════════════════════════════

class CalFilterChips extends StatelessWidget {
  const CalFilterChips({
    super.key,
    required this.counts,
    required this.filters,
    required this.onCat,
    this.orgs = const [],
    this.onOrg,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Map<CalCat, int> counts;
  final CalFilters filters;
  final ValueChanged<CalCat> onCat;
  final List<CalOrgOption> orgs;
  final ValueChanged<int>? onOrg;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chip({required Key key, required String label, required Color color, required bool on, required VoidCallback onTap, int? count, IconData? icon}) {
      final ink = appInk(context, color);
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs - 1),
              decoration: BoxDecoration(
                color: on ? c.cardBg : c.background,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: on ? Color.lerp(c.divider, c.textDark, 0.25)! : c.divider, width: AppBorder.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  width: AppSpace.xs + 2,
                  height: AppSpace.xs + 2,
                  decoration: BoxDecoration(
                    color: on ? color : color.withValues(alpha: 0),
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? color : c.textLight, width: AppBorder.strong),
                  ),
                ),
                const SizedBox(width: AppSpace.xs - 1),
                if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: on ? ink : c.textLight), const SizedBox(width: AppSpace.xxs)],
                Text(label, maxLines: 1, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: on ? c.textDark : c.textLight)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: AppSpace.xs - 2),
                  Text('$count', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textLight, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: [
          for (final k in CalCat.values)
            chip(
              key: ValueKey('cal.filter.${k.name}'),
              label: calCatLabel(k),
              color: calCatColor(c, k),
              on: !filters.hiddenCats.contains(k),
              count: counts[k],
              onTap: () => onCat(k),
            ),
          if (orgs.length > 1 && onOrg != null) ...[
            Center(child: Container(width: AppBorder.hairline, height: AppSpace.lg - 2, margin: const EdgeInsetsDirectional.only(end: AppSpace.xs), color: c.divider)),
            for (final o in orgs)
              chip(
                key: ValueKey('cal.org.${o.id}'),
                label: o.name,
                color: c.textMedium,
                icon: o.id == 0 ? Icons.person_rounded : Icons.apartment_rounded,
                on: !filters.hiddenOrgs.contains(o.id),
                onTap: () => onOrg!(o.id),
              ),
          ],
        ],
      ),
    );
  }
}

class CalFilterPanel extends StatelessWidget {
  const CalFilterPanel({
    super.key,
    required this.counts,
    required this.filters,
    required this.onCat,
    this.orgs = const [],
    this.onOrg,
  });

  final Map<CalCat, int> counts;
  final CalFilters filters;
  final ValueChanged<CalCat> onCat;
  final List<CalOrgOption> orgs;
  final ValueChanged<int>? onOrg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row({required Key key, required String label, required Color color, required bool on, required VoidCallback onTap, int? count, IconData? icon}) =>
        InkWell(
          key: key,
          borderRadius: AppRadius.chipAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs - 2),
              child: Row(children: [
                AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  width: AppIconSize.sm + 2,
                  height: AppIconSize.sm + 2,
                  decoration: BoxDecoration(
                    color: on ? color : color.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(AppSpace.xxs + 1),
                    border: Border.all(color: on ? color : c.textLight, width: AppBorder.strong),
                  ),
                  child: on ? Icon(Icons.check_rounded, size: AppIconSize.xs - 1, color: c.onHero) : null,
                ),
                const SizedBox(width: AppSpace.sm - 2),
                if (icon != null) ...[Icon(icon, size: AppIconSize.xs + 1, color: c.textMedium), const SizedBox(width: AppSpace.xs - 2)],
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: on ? c.textDark : c.textLight)),
                ),
                if (count != null && count > 0)
                  Text('$count', style: AppType.meta(context).copyWith(color: c.textLight, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _SideTitle(t('عرض', 'Show')),
      for (final k in CalCat.values)
        row(
          key: ValueKey('cal.filter.${k.name}'),
          label: calCatLabel(k),
          color: calCatColor(c, k),
          on: !filters.hiddenCats.contains(k),
          count: counts[k],
          onTap: () => onCat(k),
        ),
      if (orgs.length > 1 && onOrg != null) ...[
        const SizedBox(height: AppSpace.xs),
        _SideTitle(t('الجهات', 'Organizations')),
        for (final o in orgs)
          row(
            key: ValueKey('cal.org.${o.id}'),
            label: o.name,
            color: c.textMedium,
            icon: o.id == 0 ? Icons.person_rounded : Icons.apartment_rounded,
            on: !filters.hiddenOrgs.contains(o.id),
            onTap: () => onOrg!(o.id),
          ),
      ],
    ]);
  }
}

class _SideTitle extends StatelessWidget {
  const _SideTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xs - 2, AppSpace.xs, AppSpace.xxs),
        child: Semantics(header: true, child: Text(text, style: AppType.section(context))),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Month picker / week strip
// ═════════════════════════════════════════════════════════════════════════════

class CalMonthPicker extends StatelessWidget {
  const CalMonthPicker({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.onPick,
    required this.onMonth,
    this.dotsOf,
    this.pausedOf,
    this.rangeStart,
    this.rangeEnd,
    this.roomy = false,
    this.showHeader = true,
  });

  final DateTime month, selected, today; // wall days
  final ValueChanged<DateTime> onPick;

  /// -1 / +1: the previous / next month.
  final ValueChanged<int> onMonth;

  /// The colours of a day's events (up to three dots are drawn).
  final List<Color> Function(DateTime day)? dotsOf;
  final bool Function(DateTime day)? pausedOf;

  /// The visible range of the main view (tinted band), wall days inclusive.
  final DateTime? rangeStart, rangeEnd;

  /// Bigger cells (the phone's month view) instead of the mini picker.
  final bool roomy;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = calVisibleDays(CalView.month, month);
    final cell = roomy ? AppSpace.xxl + 2 : AppSpace.xl + 2;
    final title = _dayDate(DateTime(month.year, month.month, 15), pattern: 'MMMM y');
    Widget dayCell(DateTime d) {
      final inMonth = d.month == month.month;
      final isToday = d == today;
      final isSel = d == selected;
      final inRange = rangeStart != null && rangeEnd != null && !d.isBefore(rangeStart!) && !d.isAfter(rangeEnd!);
      final dots = dotsOf?.call(d) ?? const <Color>[];
      final paused = pausedOf?.call(d) ?? false;
      final fg = isSel ? c.onHero : (isToday ? appInk(context, c.primary) : (inMonth ? c.textDark : c.textLight.withValues(alpha: 0.6)));
      return Expanded(
        child: Semantics(
          button: true,
          selected: isSel,
          label: _dayDate(d, pattern: 'EEEE d MMMM'),
          child: InkWell(
            borderRadius: BorderRadius.circular(cell / 2),
            onTap: () => onPick(d),
            child: Container(
              height: cell + (roomy ? AppSpace.xs - 2 : AppSpace.xxs),
              decoration: BoxDecoration(
                // the main view's range: the schedule's sky band
                color: inRange && !isSel ? c.blockSky : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: cell - (roomy ? AppSpace.sm : AppSpace.xs - 2),
                  height: cell - (roomy ? AppSpace.sm : AppSpace.xs - 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? c.primary : (paused ? calTint(c, c.warning, 0.14) : null),
                    shape: BoxShape.circle,
                    border: isToday && !isSel ? Border.all(color: c.primary, width: AppBorder.strong) : null,
                  ),
                  child: Text(
                    '${d.day}',
                    maxLines: 1,
                    style: (roomy ? AppType.row(context) : AppType.meta(context))
                        .copyWith(fontWeight: isToday || isSel ? FontWeight.w600 : FontWeight.w500, color: fg, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                SizedBox(
                  height: roomy ? AppSpace.xs : AppSpace.xxs + 1,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final col in dots.take(3))
                      Container(
                        width: roomy ? AppSpace.xxs + 1 : AppSpace.xxs,
                        height: roomy ? AppSpace.xxs + 1 : AppSpace.xxs,
                        margin: const EdgeInsets.symmetric(horizontal: AppBorder.hairline),
                        decoration: BoxDecoration(color: inMonth ? col : col.withValues(alpha: 0.4), shape: BoxShape.circle),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showHeader)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xs - 2, bottom: AppSpace.xxs),
          child: Row(children: [
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
            IconButton(
              tooltip: t('الشهر السابق', 'Previous month'),
              onPressed: () => onMonth(-1),
              icon: Icon(Icons.chevron_left_rounded, color: c.textMedium),
            ),
            IconButton(
              tooltip: t('الشهر التالي', 'Next month'),
              onPressed: () => onMonth(1),
              icon: Icon(Icons.chevron_right_rounded, color: c.textMedium),
            ),
          ]),
        ),
      Row(children: [
        for (var k = 0; k < 7; k++)
          Expanded(
            child: Center(
              child: Text(
                _dayDate(days[k], pattern: roomy ? 'EEE' : 'EEEEE'),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textLight),
              ),
            ),
          ),
      ]),
      const SizedBox(height: AppSpace.xxs),
      for (var r = 0; r < 6; r++)
        if (r < 5 || days[r * 7].month == month.month) Row(children: [for (var k = 0; k < 7; k++) dayCell(days[r * 7 + k])]),
    ]);
  }
}

class CalWeekStrip extends StatelessWidget {
  const CalWeekStrip({super.key, required this.days, required this.selected, required this.today, required this.onPick, this.dotsOf});
  final List<DateTime> days;
  final DateTime selected, today;
  final ValueChanged<DateTime> onPick;
  final List<Color> Function(DateTime day)? dotsOf;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - 2, vertical: AppSpace.xxs),
      child: Row(children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              button: true,
              selected: d == selected,
              label: _dayDate(d, pattern: 'EEEE d MMMM'),
              child: InkWell(
                borderRadius: AppRadius.controlAll,
                onTap: () => onPick(d),
                child: AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  curve: AppMotion.curve,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2),
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs - 2),
                  decoration: BoxDecoration(
                    color: d == selected ? c.primary : c.primary.withValues(alpha: 0),
                    borderRadius: AppRadius.controlAll,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _dayDate(d, pattern: 'EEE'),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: AppType.overline(context).copyWith(letterSpacing: 0, color: d == selected ? c.onHeroMuted : c.textLight),
                    ),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(
                      '${d.day}',
                      style: AppType.figure(context).copyWith(color: d == selected ? c.onHero : (d == today ? appInk(context, c.primary) : c.textDark), fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: AppSpace.xxs - 1),
                    SizedBox(
                      height: AppSpace.xxs + 1,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final col in (dotsOf?.call(d) ?? const <Color>[]).take(3))
                          Container(
                            width: AppSpace.xxs,
                            height: AppSpace.xxs,
                            margin: const EdgeInsets.symmetric(horizontal: AppBorder.hairline),
                            decoration: BoxDecoration(color: d == selected ? c.onHero : col, shape: BoxShape.circle),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Agenda
// ═════════════════════════════════════════════════════════════════════════════

/// What an agenda row may do; the page wires them (the layout tests pass nothing or no-ops).
class CalTileActions {
  const CalTileActions({this.onTap, this.onJoin, this.onRsvp, this.onAnswerChange});
  final ValueChanged<CalEvent>? onTap;
  final ValueChanged<CalEvent>? onJoin;

  /// A pending invitation: `accepted` · `declined`.
  final void Function(CalEvent e, String status)? onRsvp;

  /// A one-date change a student answers: `accept` · `reject`.
  final void Function(CalEvent e, String decision)? onAnswerChange;
}

class CalAgendaList extends StatelessWidget {
  const CalAgendaList({
    super.key,
    required this.days,
    required this.nowUtc,
    this.liveKeys = const {},
    this.actions = const CalTileActions(),
    this.showOrg = false,
    this.header,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl * 2 - AppSpace.xs),
    this.controller,
    this.emptyRange,
    this.history = false,
    this.todayDone = false,
  });

  final List<CalAgendaDay> days;
  final DateTime nowUtc;
  final Set<String> liveKeys;
  final CalTileActions actions;
  final bool showOrg;
  final Widget? header, footer;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  /// Shown when no day of the range holds anything.
  final Widget? emptyRange;

  /// The list of what has finished: rows stay readable (nothing here is competing with what is coming).
  final bool history;

  /// Everything of today is over: today says so instead of "free".
  final bool todayDone;

  @override
  Widget build(BuildContext context) {
    final nothing = days.every((d) => d.events.isEmpty);
    return ListView(
      controller: controller,
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ?header,
        // the page's one entrance: the hero (index 0, in the header) then the first days, once per route
        for (final (i, d) in days.indexed) ...[
          AppReveal(
            index: i + 1,
            group: 'cal.agenda',
            rise: 6,
            cap: 4,
            child: CalAgendaDayCard(day: d, nowUtc: nowUtc, liveKeys: liveKeys, actions: actions, showOrg: showOrg, history: history, todayDone: todayDone),
          ),
          const SizedBox(height: AppSpace.xl),
        ],
        if (nothing && emptyRange != null) emptyRange!,
        ?footer,
      ],
    );
  }
}

class CalAgendaDayCard extends StatelessWidget {
  const CalAgendaDayCard({
    super.key,
    required this.day,
    required this.nowUtc,
    this.liveKeys = const {},
    this.actions = const CalTileActions(),
    this.showOrg = false,
    this.history = false,
    this.todayDone = false,
  });

  final CalAgendaDay day;
  final DateTime nowUtc;
  final Set<String> liveKeys;
  final CalTileActions actions;
  final bool showOrg, history, todayDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nowWall = AppTime.toZone(nowUtc);
    final count = day.events.where((e) => !e.cancelled).length;
    final rows = <Widget>[];
    for (var i = 0; i <= day.events.length; i++) {
      if (day.today && day.nowAt == i && day.events.isNotEmpty && !history) rows.add(CalNowLine(label: AppTime.time(nowUtc)));
      if (i == day.events.length) break;
      final e = day.events[i];
      if (i > 0 && rows.last is! CalNowLine) rows.add(const SizedBox(height: AppSpace.xs));
      rows.add(CalAgendaTile(
        event: e,
        nowUtc: nowUtc,
        live: calIsLive(e, nowUtc, liveKeys: liveKeys),
        joinable: calJoinable(e, nowUtc, liveKeys: liveKeys),
        past: calIsOver(e, nowUtc, liveKeys: liveKeys),
        history: history,
        showOrg: showOrg,
        actions: actions,
      ));
    }
    final dateLine = _dayDate(day.day, pattern: calDay(day.day).difference(calDay(nowWall)).inDays.abs() <= 1 ? 'EEEE d MMMM' : 'd MMMM y');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs / 2, AppSpace.xxs / 2, AppSpace.xxs, AppSpace.sm),
        child: Row(children: [
          // the date tile: paper on a hairline; today wears the schedule's sky tone
          Container(
            width: AppTouch.min,
            height: AppTouch.min + AppSpace.xxs,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: day.today ? c.blockSky : c.cardBg,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: day.today ? c.blockSky : c.divider, width: AppBorder.hairline),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_dayDate(day.day, pattern: 'MMM'), maxLines: 1, style: AppType.overline(context).copyWith(letterSpacing: 0, height: 1.1, color: day.today ? c.blockMuted(c.blockSky) : c.textLight)),
                Text('${day.day.day}', maxLines: 1, style: AppType.section(context).copyWith(height: 1.05)),
              ]),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(_dayTitle(day.day, nowWall), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              ),
              // the count rides on the date line, beside the title: at the row's END it sat under the assistant's
              // docked edge tab on phones (R3), which docks on that side by default
              Row(children: [
                Flexible(child: Text(dateLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
                if (count > 0) Text(' · ${calEventsText(count)}', maxLines: 1, style: AppType.meta(context)),
              ]),
            ]),
          ),
        ]),
      ),
      for (final p in day.pauses) ...[CalPauseBanner(pause: p), const SizedBox(height: AppSpace.xs)],
      if (day.events.isEmpty) CalFreeDay(today: day.today, done: day.today && todayDone) else ...rows,
    ]);
  }
}

/// "1 event" · "2 events" (Arabic's four forms).
String calEventsText(int n) => countText(n, ar1: 'موعد واحد', ar2: 'موعدان', arFew: '{n} مواعيد', arMany: '{n} موعدًا', en1: '1 event', en: '{n} events');

// ═════════════════════════════════════════════════════════════════════════════
//  The head of the list
// ═════════════════════════════════════════════════════════════════════════════

/// Lets [child] reach the screen edges through the list's side [gutter]: a horizontal strip scrolls off the edge.
class CalBleed extends StatelessWidget {
  const CalBleed({super.key, required this.gutter, required this.child});
  final double gutter;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          height: 44,
          child: OverflowBox(minWidth: box.maxWidth + gutter * 2, maxWidth: box.maxWidth + gutter * 2, child: child),
        ),
      );
}

/// Today in one look: the date, what is left today and the next event (Join when its room is open).
class CalTodayHero extends StatelessWidget {
  const CalTodayHero({
    super.key,
    required this.nowUtc,
    required this.left,
    this.week = 0,
    this.invites = 0,
    this.next,
    this.nextJoinable = false,
    this.onTapNext,
    this.onJoinNext,
  });

  final DateTime nowUtc;

  /// Events still to come today, and in the next seven days.
  final int left, week;
  final int invites;
  final CalEvent? next;
  final bool nextJoinable;
  final VoidCallback? onTapNext, onJoinNext;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final leftText = countText(left,
        ar0: 'لا مواعيد متبقية اليوم',
        en0: 'Nothing left today',
        ar1: 'موعد واحد متبقٍ اليوم',
        ar2: 'موعدان متبقيان اليوم',
        arFew: '{n} مواعيد متبقية اليوم',
        arMany: '{n} موعدًا متبقيًا اليوم',
        en1: '1 event left today',
        en: '{n} events left today');
    final n = next;
    final nextWhen = n == null ? null : (calWhen(n, nowUtc, toWall: AppTime.toZone) ?? '${AppTime.date(n.start, pattern: 'EEE d MMM')} · ${AppTime.time(n.start)}');
    final bc = AppBlockColors.of(context, AppBlockTone.sky);
    Widget figure(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          AppCountUp(value, memoryKey: 'cal.hero.$label', style: AppType.figureLarge(context).copyWith(color: bc.ink)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: bc.muted)),
        ]);
    return AppTilt(
      radius: AppRadius.block,
      maxTilt: 2,
      touchTilt: false,
      shadowStrength: 0.5,
      child: AppBlock(
        tone: AppBlockTone.sky,
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md + AppSpace.xxs),
        child: LayoutBuilder(builder: (context, box) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // the day as an editorial numeral, the weekday over it: the one big thing of the page
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(AppTime.date(nowUtc, pattern: 'EEE'), maxLines: 1, style: AppType.label(context).copyWith(color: bc.muted, height: 1.1)),
                Text(AppTime.date(nowUtc, pattern: 'd'), maxLines: 1, style: AppType.display(context).copyWith(color: bc.ink, height: 1.0, fontFeatures: const [FontFeature.liningFigures()])),
              ]),
              const SizedBox(width: AppSpace.md),
              Container(width: AppBorder.hairline, height: AppTouch.min, color: bc.faint.withValues(alpha: 0.35)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppTime.date(nowUtc, pattern: 'EEEE d MMMM'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: bc.ink)),
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(leftText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: bc.muted)),
                ]),
              ),
              if (box.maxWidth >= 560) ...[
                const SizedBox(width: AppSpace.md),
                figure('$week', t('خلال 7 أيام', 'Next 7 days')),
                if (invites > 0) ...[
                  const SizedBox(width: AppSpace.lg),
                  figure('$invites', t('دعوات', 'Invitations')),
                ],
              ],
            ]),
            if (n != null) ...[
              const SizedBox(height: AppSpace.md),
              Material(
                color: c.cardBg,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: bc.border ?? c.divider, width: AppBorder.hairline)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('cal.hero.next'),
                  onTap: onTapNext,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xs),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                      child: Row(children: [
                        Icon(calSourceIcon(n.source), size: AppIconSize.md, color: calEventColor(c, n)),
                        const SizedBox(width: AppSpace.sm - 2),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                            Text('${t('التالي', 'Next')} · $nextWhen', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                          ]),
                        ),
                        if (nextJoinable && onJoinNext != null) ...[
                          const SizedBox(width: AppSpace.xs),
                          AppButton.primary(
                            key: const ValueKey('cal.hero.join'),
                            label: t('انضم', 'Join'),
                            icon: Icons.videocam_rounded,
                            size: AppButtonSize.sm,
                            onPressed: onJoinNext,
                          ),
                        ] else
                          Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ]);
        }),
      ),
    );
  }
}

/// A room open right now: above every other row of the list, Join within thumb's reach.
class CalLiveNowCard extends StatelessWidget {
  const CalLiveNowCard({super.key, required this.event, required this.nowUtc, this.onTap, this.onJoin});
  final CalEvent event;
  final DateTime nowUtc;
  final VoidCallback? onTap, onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final when = calWhen(e, nowUtc, toWall: AppTime.toZone);
    final radius = AppRadius.blockAll;
    return Semantics(
      button: onTap != null,
      label: '${t('مباشر الآن', 'Live now')}: ${e.title}',
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.danger, width: AppBorder.strong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const CalLiveDot(),
                    const SizedBox(width: AppSpace.xs - 2),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: t('مباشر الآن', 'Live now'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.danger))),
                          if (when != null) TextSpan(text: '  ·  $when', style: AppType.meta(context)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.xxs),
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  if ((e.subtitle ?? '').isNotEmpty)
                    Text(e.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              if (onJoin != null) ...[
                const SizedBox(width: AppSpace.sm),
                AppButton.primary(
                  key: ValueKey('cal.join.${e.id}'),
                  label: t('انضم', 'Join'),
                  icon: Icons.videocam_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onJoin,
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section's title with the one action that flips the list.
class CalListBar extends StatelessWidget {
  const CalListBar({super.key, required this.title, required this.actionLabel, required this.actionIcon, required this.onAction, this.actionKey});
  final String title, actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final String? actionKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs / 2, bottom: AppSpace.xxs),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)))),
        Flexible(
          child: TextButton.icon(
            key: actionKey == null ? null : ValueKey<String>(actionKey!),
            onPressed: onAction,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.textMedium),
            icon: Icon(actionIcon, size: AppIconSize.sm + 2),
            label: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

/// The red "now" line between the agenda rows of today.
class CalNowLine extends StatelessWidget {
  const CalNowLine({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: t('الآن $label', 'Now $label'),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm - 2, AppSpace.xxs / 2, AppSpace.sm, AppSpace.xxs / 2),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 1, vertical: AppSpace.xxs / 2),
            decoration: BoxDecoration(color: c.dangerBase, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text(label, maxLines: 1, style: AppType.overline(context).copyWith(letterSpacing: 0, color: c.onHero, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Container(width: AppSpace.xs - 1, height: AppSpace.xs - 1, decoration: BoxDecoration(color: c.dangerBase, shape: BoxShape.circle)),
          Expanded(child: Container(height: AppBorder.strong, color: c.dangerBase)),
        ]),
      ),
    );
  }
}

class CalFreeDay extends StatelessWidget {
  const CalFreeDay({super.key, this.today = false, this.done = false});
  final bool today;

  /// Today had events and all of them are over.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(children: [
        Icon(done ? Icons.task_alt_rounded : Icons.wb_sunny_rounded, color: c.textLight, size: AppIconSize.lg - 2),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(done ? t('انتهت مواعيد اليوم', "You're done for today") : (today ? t('لا شيء اليوم', 'Nothing today') : t('يوم فارغ', 'A free day')),
                style: AppType.bodyStrong(context)),
            Text(done ? t('ما انتهى تجده في السابقة والمنتهية', 'What finished is under Past and ended') : t('لا محاضرات ولا اجتماعات — وقتك لك', 'No classes, no meetings — the time is yours'),
                style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

class CalPauseBanner extends StatelessWidget {
  const CalPauseBanner({super.key, required this.pause, this.compact = false});
  final CalPause pause;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.warning);
    final range = pause.start == pause.end
        ? _dayDate(pause.start, pattern: 'd MMM')
        : '${_dayDate(pause.start, pattern: 'd MMM')} – ${_dayDate(pause.end, pattern: 'd MMM')}';
    final name = pause.name.isEmpty ? t('فترة الامتحانات', 'Exam period') : pause.name;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.md - 2, vertical: compact ? AppSpace.xs : AppSpace.sm - 1),
      decoration: BoxDecoration(
        color: calTint(c, c.warning, 0.10),
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: c.warning.withValues(alpha: 0.30), width: AppBorder.hairline),
      ),
      child: Row(children: [
        Icon(Icons.pause_circle_rounded, color: ink, size: AppIconSize.md),
        const SizedBox(width: AppSpace.sm - 2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(fontSize: AppType.label(context).fontSize)),
            Text(
              [
                t('المحاضرات الأسبوعية متوقفة', 'Weekly classes paused'),
                range,
                if ((pause.orgName ?? '').isNotEmpty) pause.orgName!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The tags of an event: live / now · online · substitute · cancelled · my answer · kind.
List<Widget> calTagsOf(BuildContext context, CalEvent e, {required bool live, required DateTime nowUtc}) {
  final c = context.colors;
  final ch = e.change;
  return [
    if (e.cancelled) CalTag(t('أُلغيت', 'Cancelled'), c.danger, icon: Icons.event_busy_rounded),
    if (e.ended) CalTag(t('انتهى', 'Ended'), c.textMedium, icon: Icons.task_alt_rounded),
    if (live) CalTag(t('مباشر الآن', 'Live now'), c.danger, icon: Icons.sensors_rounded, solid: true),
    if (!e.cancelled && ch != null && ch.online) CalTag(t('أونلاين هذه المرة', 'Online this time'), c.primary, icon: Icons.videocam_rounded),
    if (!e.cancelled && ch != null && ch.substitute) CalTag(t('مدرس بديل', 'Substitute'), c.warning, icon: Icons.person_pin_rounded),
    if (!e.cancelled && ch != null && ch.mode == 'offline') CalTag(t('حضورياً هذه المرة', 'In person this time'), c.success, icon: Icons.meeting_room_rounded),
    if (e.source == 'timetable' && e.kind == 'lab') CalTag(t('معمل', 'Lab'), calEventColor(c, e)),
    if (e.source == 'exam' && e.kind == 'midterm') CalTag(t('منتصف الفصل', 'Midterm'), c.danger),
    if (e.source == 'exam' && e.kind == 'final') CalTag(t('نهائي', 'Final'), c.danger),
    if (e.isMeeting && e.mode == 'online' && !live && !e.ended) CalTag(t('أونلاين', 'Online'), c.primary, icon: Icons.videocam_rounded),
    if (e.isMeeting && !e.isOwner && e.myStatus != null && e.myStatus != 'owner' && !e.ended)
      CalTag(calStatusLabel(e.myStatus), calStatusColor(c, e.myStatus), icon: calStatusIcon(e.myStatus)),
    if (e.isMeeting && e.isOwner) CalTag(t('أنت المنظّم', 'You organize'), c.textMedium, icon: Icons.star_rounded),
  ];
}

class CalAgendaTile extends StatelessWidget {
  const CalAgendaTile({
    super.key,
    required this.event,
    required this.nowUtc,
    this.live = false,
    this.joinable = false,
    this.past = false,
    this.history = false,
    this.showOrg = false,
    this.actions = const CalTileActions(),
  });

  final CalEvent event;
  final DateTime nowUtc;
  final bool live, joinable, past, history, showOrg;
  final CalTileActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final color = calEventColor(c, e);
    final struck = e.cancelled || e.declined;
    final muted = struck || e.ended;
    final when = calWhen(e, nowUtc, toWall: AppTime.toZone);
    final meta = [
      if (e.source != 'timetable' || e.kind != 'lab') calSourceLabelShort(e),
      if ((e.subtitle ?? '').isNotEmpty && !e.isMeeting) e.subtitle!,
      if (e.online && !e.isMeeting) t('أونلاين', 'Online') else if ((e.location ?? '').isNotEmpty && e.location != 'online') e.location!,
      if (showOrg && (e.orgName ?? '').isNotEmpty) e.orgName!,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    final tags = calTagsOf(context, e, live: live, nowUtc: nowUtc);
    final pendingInvite = e.isMeeting && e.myStatus == 'pending' && actions.onRsvp != null && !past;
    final answerChange = e.change != null && e.change!.canRespond && !e.cancelled && actions.onAnswerChange != null && !past;
    final allDay = e.wallEnd.difference(e.wallStart).inHours >= 20;

    final join = joinable && actions.onJoin != null
        ? AppButton.primary(
            key: ValueKey('cal.join.${e.id}'),
            label: t('انضم', 'Join'),
            icon: Icons.videocam_rounded,
            size: AppButtonSize.sm,
            onPressed: () => actions.onJoin!(e),
          )
        : null;

    final body = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md + AppSpace.xxs, AppSpace.sm + AppSpace.xxs / 2, AppSpace.sm, AppSpace.sm + AppSpace.xxs / 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: AppSpace.xxxl - 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (allDay)
              Text(t('طوال اليوم', 'All day'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))
            else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(AppTime.time(e.start), maxLines: 1, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: muted ? c.textMedium : c.textDark, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(height: AppSpace.xxs / 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(AppTime.time(e.end), maxLines: 1, style: AppType.meta(context).copyWith(color: c.textLight, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(context).copyWith(
                    color: muted ? c.textMedium : c.textDark,
                    decoration: struck ? TextDecoration.lineThrough : null,
                    decorationColor: c.textLight,
                  ),
                ),
              ),
              if (join != null) ...[const SizedBox(width: AppSpace.xs), join],
            ]),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs - 1),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs / 2, end: AppSpace.xxs),
                  child: Icon(calSourceIcon(e.source), size: AppIconSize.xs - 1, color: muted ? c.textLight : appInk(context, color)),
                ),
                Expanded(child: Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
              ]),
            ],
            if (tags.isNotEmpty || when != null) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (live) const CalLiveDot(),
                ...tags,
                if (when != null && !past)
                  Text(when, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: live ? appInk(context, c.danger) : c.textLight)),
              ]),
            ],
            if (pendingInvite || answerChange) ...[
              const SizedBox(height: AppSpace.sm - 2),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (pendingInvite) ...[
                  _MiniAction(key: ValueKey('cal.accept.${e.id}'), label: t('قبول', 'Accept'), icon: Icons.check_rounded, color: c.success, onTap: () => actions.onRsvp!(e, 'accepted')),
                  _MiniAction(key: ValueKey('cal.decline.${e.id}'), label: t('اعتذار', 'Decline'), icon: Icons.close_rounded, color: c.danger, outline: true, onTap: () => actions.onRsvp!(e, 'declined')),
                  if (actions.onTap != null)
                    _MiniAction(label: t('اقترح موعداً', 'Propose a time'), icon: Icons.schedule_send_rounded, color: c.textMedium, outline: true, onTap: () => actions.onTap!(e)),
                ],
                if (answerChange) ...[
                  _MiniAction(
                    key: ValueKey('cal.change.accept.${e.id}'),
                    label: e.change!.myResponse == 'accept' ? t('قبلت التغيير', 'You accepted') : t('قبول التغيير', 'Accept change'),
                    icon: e.change!.myResponse == 'accept' ? Icons.check_circle_rounded : Icons.check_rounded,
                    color: c.success,
                    outline: e.change!.myResponse == 'reject',
                    onTap: () => actions.onAnswerChange!(e, 'accept'),
                  ),
                  _MiniAction(
                    key: ValueKey('cal.change.reject.${e.id}'),
                    label: e.change!.myResponse == 'reject' ? t('رفضت التغيير', 'You rejected') : t('رفض', 'Reject'),
                    icon: e.change!.myResponse == 'reject' ? Icons.cancel_rounded : Icons.close_rounded,
                    color: c.danger,
                    outline: e.change!.myResponse != 'reject',
                    onTap: () => actions.onAnswerChange!(e, 'reject'),
                  ),
                ],
              ]),
            ],
          ]),
        ),
      ]),
    );

    // paper on a warm hairline, no resting shadow (tone first); a live row draws its edge in the danger tone
    final radius = AppRadius.cardAll;
    return Semantics(
      button: actions.onTap != null,
      label: '${e.title}, ${AppTime.time(e.start)}',
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: live ? c.danger : c.divider, width: live ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: actions.onTap == null ? null : () => actions.onTap!(e),
          child: Stack(children: [
            Opacity(opacity: past && !live && !history ? 0.55 : 1, child: body),
            // the kind's colour as a slim rule inside the card's start, the height of the card whatever it holds
            PositionedDirectional(
              start: AppSpace.xs - 2,
              top: AppSpace.sm,
              bottom: AppSpace.sm,
              width: AppSpace.xxs - 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: muted ? c.textLight.withValues(alpha: 0.35) : (past ? color.withValues(alpha: 0.5) : color),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Lecture" · "Exam" · "Meeting" · "Live session" — the first word of a row's meta line.
String calSourceLabelShort(CalEvent e) => switch (e.source) {
      'timetable' => e.kind == 'lab' ? t('معمل', 'Lab') : (e.kind == 'section' ? t('سكشن', 'Section') : t('محاضرة', 'Lecture')),
      'extra' => t('فترة خاصة', 'Special period'),
      'exam' => t('امتحان', 'Exam'),
      'course_session' => t('جلسة مباشرة', 'Live session'),
      'course_weekly' => t('موعد المقرر', 'Course appointment'),
      'meeting' => e.kind == 'private' ? t('موعد خاص', 'Private') : t('اجتماع', 'Meeting'),
      _ => '',
    };

class _MiniAction extends StatelessWidget {
  const _MiniAction({super.key, required this.label, required this.icon, required this.color, required this.onTap, this.outline = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, color);
    return InkWell(
      borderRadius: AppRadius.controlAll,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: outline ? c.cardBg : calTint(c, color, 0.12),
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: outline ? Color.lerp(c.divider, c.textDark, 0.2)! : color.withValues(alpha: 0.35), width: AppBorder.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppIconSize.sm, color: outline ? c.textMedium : ink),
          const SizedBox(width: AppSpace.xs - 2),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: outline ? c.textMedium : ink))),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Event details (everything but meetings: those open MeetingSheet)
// ═════════════════════════════════════════════════════════════════════════════

class CalEventSheet extends StatelessWidget {
  const CalEventSheet({
    super.key,
    required this.event,
    required this.nowUtc,
    this.live = false,
    this.joinable = false,
    this.onJoin,
    this.onOpenCourse,
    this.onCourseDetails,
    this.onOpenExams,
    this.onOpenTimetable,
    this.onAnswer,
    this.onOpenLink,
    this.onUndo,
    this.busy = false,
  });

  final CalEvent event;
  final DateTime nowUtc;
  final bool live, joinable, busy;
  final VoidCallback? onJoin, onOpenCourse, onCourseDetails, onOpenExams, onOpenTimetable, onOpenLink, onUndo;
  final ValueChanged<String>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final color = calEventColor(c, e);
    final ch = e.change;
    final when = calWhen(e, nowUtc, toWall: AppTime.toZone);
    Widget line(IconData icon, String text, {Color? tone}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs - 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: AppIconSize.md - 1, color: tone ?? c.textLight),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textDark))),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg - 4, AppSpace.xxs, AppSpace.lg - 4, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppTouch.min - 2,
            height: AppTouch.min - 2,
            decoration: BoxDecoration(color: calTint(c, color, 0.14), borderRadius: AppRadius.controlAll),
            child: Icon(calSourceIcon(e.source), color: appInk(context, color), size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.md - 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(calSourceLabelShort(e), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, color))),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(
                e.title,
                style: AppType.headline(context)
                    .copyWith(color: e.cancelled ? c.textLight : c.textDark, decoration: e.cancelled ? TextDecoration.lineThrough : null),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [
          if (live) const CalLiveDot(),
          ...calTagsOf(context, e, live: live, nowUtc: nowUtc),
          if (when != null) CalTag(when, c.textMedium, icon: Icons.schedule_rounded),
        ]),
        const SizedBox(height: AppSpace.sm - 2),
        line(Icons.event_rounded, '${AppTime.date(e.start, pattern: 'EEEE d MMMM')} · ${AppTime.time(e.start)} – ${AppTime.time(e.end)}'),
        if (e.online && !e.isMeeting)
          line(Icons.videocam_rounded, t('أونلاين', 'Online'))
        else if ((e.location ?? '').isNotEmpty)
          line(Icons.place_rounded, e.location!),
        if ((e.subtitle ?? '').isNotEmpty) line(e.source == 'timetable' ? Icons.person_rounded : Icons.info_outline_rounded, e.subtitle!),
        if ((e.orgName ?? '').isNotEmpty) line(Icons.apartment_rounded, e.orgName!),
        if (ch != null && (ch.online || ch.substitute || ch.cancelled || ch.mode == 'offline')) ...[
          const SizedBox(height: AppSpace.sm - 2),
          Container(
            padding: const EdgeInsets.all(AppSpace.md - 2),
            decoration: BoxDecoration(
              color: calTint(c, ch.cancelled ? c.danger : (ch.online ? c.primary : c.warning), 0.08),
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: (ch.cancelled ? c.danger : (ch.online ? c.primary : c.warning)).withValues(alpha: 0.28), width: AppBorder.hairline),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                ch.cancelled
                    ? t('أُلغيت حصة هذا اليوم', 'This date is cancelled')
                    : ch.online
                        ? t('تُعقد هذه الحصة أونلاين', 'This date is held online')
                        : ch.substitute
                            ? t('يدرّس هذه الحصة مدرس بديل', 'A substitute teaches this date')
                            : t('تعود الحصة حضورياً', 'Back in person on this date'),
                style: AppType.bodyStrong(context),
              ),
              if ((ch.note ?? '').isNotEmpty) ...[const SizedBox(height: AppSpace.xxs), Text(ch.note!, style: AppType.meta(context))],
              if (ch.canRespond || ch.canEdit) ...[
                const SizedBox(height: AppSpace.xs - 2),
                Text(t('قبِل ${ch.accept} · رفض ${ch.reject}', '${ch.accept} accepted · ${ch.reject} rejected'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: AppSpace.sm - 2),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (ch.online && (ch.onlineUrl ?? '').isNotEmpty && onOpenLink != null)
                  _MiniAction(label: t('رابط الحصة', 'Session link'), icon: Icons.link_rounded, color: c.primary, onTap: onOpenLink!),
                if (ch.canRespond && !ch.cancelled && onAnswer != null) ...[
                  _MiniAction(
                    label: ch.myResponse == 'accept' ? t('قبلت', 'Accepted') : t('قبول', 'Accept'),
                    icon: ch.myResponse == 'accept' ? Icons.check_circle_rounded : Icons.check_rounded,
                    color: c.success,
                    outline: ch.myResponse == 'reject',
                    onTap: busy ? () {} : () => onAnswer!('accept'),
                  ),
                  _MiniAction(
                    label: ch.myResponse == 'reject' ? t('رفضت', 'Rejected') : t('رفض', 'Reject'),
                    icon: ch.myResponse == 'reject' ? Icons.cancel_rounded : Icons.close_rounded,
                    color: c.danger,
                    outline: ch.myResponse != 'reject',
                    onTap: busy ? () {} : () => onAnswer!('reject'),
                  ),
                ],
                if (ch.canEdit && onUndo != null)
                  _MiniAction(label: t('إلغاء التغيير', 'Undo the change'), icon: Icons.undo_rounded, color: c.textMedium, outline: true, onTap: onUndo!),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: AppSpace.lg - 6),
        if (joinable && onJoin != null) ...[
          AppButton.primary(label: live ? t('انضم الآن', 'Join now') : t('انضم', 'Join'), icon: Icons.videocam_rounded, onPressed: onJoin, expand: true),
          const SizedBox(height: AppSpace.sm - 2),
        ],
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (onOpenCourse != null) AppPill(icon: Icons.menu_book_rounded, label: t('فتح المقرر', 'Open course'), onTap: onOpenCourse),
          if (onCourseDetails != null)
            AppPill(icon: Icons.insights_rounded, label: t('تقدمي في المقرر', 'Course progress'), onTap: onCourseDetails),
          if (onOpenExams != null) AppPill(icon: Icons.assignment_rounded, label: t('امتحاناتي', 'My exams'), onTap: onOpenExams),
          if (onOpenTimetable != null) AppPill(icon: Icons.view_week_rounded, label: t('جدولي في الجهة', 'My timetable'), onTap: onOpenTimetable),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Desktop sidebar cards
// ═════════════════════════════════════════════════════════════════════════════

class CalUpNextCard extends StatelessWidget {
  const CalUpNextCard({super.key, required this.event, required this.nowUtc, this.live = false, this.onTap});
  final CalEvent event;
  final DateTime nowUtc;
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final when = calWhen(e, nowUtc, toWall: AppTime.toZone) ?? AppTime.date(e.start, pattern: 'EEE d MMM');
    final bc = AppBlockColors.of(context, live ? AppBlockTone.paper : AppBlockTone.sky);
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (live) ...[const CalLiveDot(), const SizedBox(width: AppSpace.xs - 2)],
        Expanded(
          child: Text(live ? t('مباشر الآن', 'Live now') : t('التالي', 'Up next'),
              style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: live ? appInk(context, c.danger) : bc.muted)),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: bc.ink))),
      ]),
      const SizedBox(height: AppSpace.sm - 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(AppTime.time(e.start), maxLines: 1, style: AppType.display(context).copyWith(color: bc.ink, height: 1.05)),
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: bc.ink)),
      const SizedBox(height: AppSpace.xxs),
      Text(
        [calSourceLabelShort(e), if ((e.location ?? '').isNotEmpty) e.location!, if ((e.orgName ?? '').isNotEmpty) e.orgName!].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context).copyWith(color: bc.muted),
      ),
    ]);
    if (live) {
      return Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.blockAll, side: BorderSide(color: c.danger, width: AppBorder.strong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(AppSpace.md + AppSpace.xxs), child: content)),
      );
    }
    return AppTilt.subtle(
      radius: AppRadius.block,
      child: AppBlock(tone: AppBlockTone.sky, padding: const EdgeInsets.all(AppSpace.md + AppSpace.xxs), onTap: onTap, child: content),
    );
  }
}

class CalInvitesCard extends StatelessWidget {
  const CalInvitesCard({super.key, required this.invites, this.actions = const CalTileActions()});
  final List<CalEvent> invites;
  final CalTileActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.mark_email_unread_rounded, size: AppIconSize.sm + 2, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(t('دعوات بانتظار ردك', 'Invitations to answer'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
          AppCountBadgePill(count: invites.length),
        ]),
        for (final e in invites.take(3)) ...[
          const SizedBox(height: AppSpace.sm),
          InkWell(
            onTap: actions.onTap == null ? null : () => actions.onTap!(e),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              Text('${AppTime.date(e.start, pattern: 'EEE d MMM')} · ${AppTime.time(e.start)}', style: AppType.meta(context)),
            ]),
          ),
          if (actions.onRsvp != null) ...[
            const SizedBox(height: AppSpace.xs - 2),
            Wrap(spacing: AppSpace.xs - 2, runSpacing: AppSpace.xs - 2, children: [
              _MiniAction(label: t('قبول', 'Accept'), icon: Icons.check_rounded, color: c.success, onTap: () => actions.onRsvp!(e, 'accepted')),
              _MiniAction(label: t('اعتذار', 'Decline'), icon: Icons.close_rounded, color: c.danger, outline: true, onTap: () => actions.onRsvp!(e, 'declined')),
            ]),
          ],
        ],
      ]),
    );
  }
}

/// A small count in the primary tint (the invitations card's head).
class AppCountBadgePill extends StatelessWidget {
  const AppCountBadgePill({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: AppSpace.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 1, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: calTint(c, c.primary, 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary), fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Loading
// ═════════════════════════════════════════════════════════════════════════════

class CalScheduleSkeleton extends StatelessWidget {
  const CalScheduleSkeleton({super.key, required this.view, this.bare = false});
  final CalView view;

  /// Only the day rows, inside a list that already has its head.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (view == CalView.agenda) {
      Widget day(int rows) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                AppSkeletonBox(width: 46, height: 50, radius: 14),
                SizedBox(width: AppSpace.sm),
                AppSkeletonBox(width: 120, height: 14),
              ]),
              const SizedBox(height: AppSpace.sm),
              for (var i = 0; i < rows; i++)
                Container(
                  margin: EdgeInsets.only(bottom: i == rows - 1 ? 0 : AppSpace.xs),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AppSkeletonBox(width: 48, height: 12),
                      SizedBox(height: 6),
                      AppSkeletonBox(width: 36, height: 10),
                    ]),
                    SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AppSkeletonBox(height: 13),
                        SizedBox(height: 8),
                        AppSkeletonBox(width: 150, height: 10),
                      ]),
                    ),
                  ]),
                ),
            ]),
          );
      if (bare) return AppShimmer(child: Column(mainAxisSize: MainAxisSize.min, children: [day(2), day(2)]));
      return AppShimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            const Padding(padding: EdgeInsets.only(bottom: AppSpace.lg), child: AppSkeletonBox(height: 118, radius: AppRadius.block)),
            day(3),
            day(2),
            day(2),
          ],
        ),
      );
    }
    // grids: a header row and a few blocks
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [for (var i = 0; i < (view == CalView.day ? 1 : 7); i++) const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: AppSkeletonBox(height: 30, radius: 10)))]),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final cols = view == CalView.day ? 1 : 7;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < cols; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(children: [
                        SizedBox(height: 20.0 + (i % 3) * 30),
                        AppSkeletonBox(height: 56 + (i % 2) * 24, radius: 10),
                        const SizedBox(height: 14),
                        if (i % 2 == 0) const AppSkeletonBox(height: 44, radius: 10),
                      ]),
                    ),
                  ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}
