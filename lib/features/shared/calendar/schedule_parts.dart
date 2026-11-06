// lib/features/shared/calendar/schedule_parts.dart — the presentational pieces of the one schedule page (D-085).
//
// Plain values in, callbacks out (no provider, no API), so test/ui/schedule_layout_test.dart pumps each one at
// 320×640 and 1400×900, Arabic + English, text ×1.3:
//
//   CalViewSwitch       Agenda · Day · Week · Month, a segmented pill
//   CalFilterChips      the kinds (+ organizations) as chips with their counts — phone / tablet
//   CalFilterPanel      the same as a list with colour checks — the desktop sidebar
//   CalMonthPicker      a month of days with event dots, today ring, the selected day / range; mini (sidebar,
//                       phone header) or roomy (the phone's month view)
//   CalWeekStrip        seven day pills with dots (the phone's day view)
//   CalAgendaList       days → CalAgendaDayCard (header + rows + the "now" line + exam-window banner), free-day note
//   CalAgendaTile       one event: time column, colour bar, title, meta, tags (live · online · substitute · cancelled
//                       · my answer), inline Join / Accept · Decline / the change's Accept · Reject
//   CalEventSheet       a non-meeting event's details: time, place, people, the one-date change with its answers,
//                       Join / Open course / My exams / My timetable
//   CalUpNextCard · CalInvitesCard   the desktop sidebar's "Up next" and pending invitations
//   CalScheduleSkeleton the loading state of each view (shimmer, never a spinner)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : calTint(c, color, 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: ink), const SizedBox(width: 4)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w700, c: ink)),
        ),
      ]),
    );
  }
}

/// The pulsing-free live dot (a decorative pulse would need syncMotionLoop; a still dot tells the same).
class CalLiveDot extends StatelessWidget {
  const CalLiveDot({super.key, this.size = 8});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.danger,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.danger.withValues(alpha: 0.45), blurRadius: size, spreadRadius: 1)],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  View switch
// ═════════════════════════════════════════════════════════════════════════════

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
          borderRadius: BorderRadius.circular(10),
          onTap: () => onView(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.cardBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on ? [BoxShadow(color: c.textDark.withValues(alpha: c.isDark ? 0.0 : 0.08), blurRadius: 6, offset: const Offset(0, 2))] : null,
              border: on && c.isDark ? Border.all(color: c.divider) : null,
            ),
            child: Text(
              calViewLabel(v),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(13, w: on ? FontWeight.w800 : FontWeight.w600, c: on ? c.textDark : c.textMedium),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(13)),
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
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: on ? calTint(c, color, 0.12) : c.cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? color.withValues(alpha: 0.45) : c.divider),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: on ? color : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? color : c.textLight, width: 1.6),
                  ),
                ),
                const SizedBox(width: 7),
                if (icon != null) ...[Icon(icon, size: 14, color: on ? ink : c.textLight), const SizedBox(width: 4)],
                Text(label, maxLines: 1, style: appText(12.5, w: FontWeight.w700, c: on ? ink : c.textMedium)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: appText(11.5, w: FontWeight.w800, c: on ? ink.withValues(alpha: 0.75) : c.textLight)),
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
            Center(child: Container(width: 1, height: 22, margin: const EdgeInsetsDirectional.only(end: 8), color: c.divider)),
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
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: on ? color : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: on ? color : c.textLight, width: 1.6),
                  ),
                  child: on ? Icon(Icons.check_rounded, size: 13, color: c.onHero) : null,
                ),
                const SizedBox(width: 10),
                if (icon != null) ...[Icon(icon, size: 15, color: c.textMedium), const SizedBox(width: 6)],
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: on ? c.textDark : c.textLight)),
                ),
                if (count != null && count > 0) Text('$count', style: appText(12, w: FontWeight.w700, c: c.textLight)),
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
        const SizedBox(height: 8),
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
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
        child: Text(text.toUpperCase(), style: appText(11, w: FontWeight.w800, c: context.colors.textLight).copyWith(letterSpacing: 0.8)),
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
    final cell = roomy ? 50.0 : 34.0;
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
              height: cell + (roomy ? 6 : 4),
              decoration: BoxDecoration(
                color: inRange && !isSel ? calTint(c, c.primary, 0.07) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: cell - (roomy ? 12 : 6),
                  height: cell - (roomy ? 12 : 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? c.primary : (paused ? calTint(c, c.warning, 0.14) : null),
                    shape: BoxShape.circle,
                    border: isToday && !isSel ? Border.all(color: c.primary, width: 1.6) : null,
                  ),
                  child: Text(
                    '${d.day}',
                    maxLines: 1,
                    style: appText(roomy ? 15 : 12, w: isToday || isSel ? FontWeight.w800 : FontWeight.w600, c: fg),
                  ),
                ),
                SizedBox(
                  height: roomy ? 8 : 5,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final col in dots.take(3))
                      Container(
                        width: roomy ? 5 : 4,
                        height: roomy ? 5 : 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
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
          padding: const EdgeInsetsDirectional.only(start: 6, bottom: 4),
          child: Row(children: [
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(roomy ? 16 : 14, w: FontWeight.w800, c: c.textDark)),
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
                style: appText(11, w: FontWeight.w700, c: c.textLight),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              button: true,
              selected: d == selected,
              label: _dayDate(d, pattern: 'EEEE d MMMM'),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPick(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: d == selected ? c.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _dayDate(d, pattern: 'EEE'),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: appText(10.5, w: FontWeight.w700, c: d == selected ? c.onHeroMuted : c.textLight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.day}',
                      style: appText(16, w: FontWeight.w800, c: d == selected ? c.onHero : (d == today ? appInk(context, c.primary) : c.textDark)),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 5,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final col in (dotsOf?.call(d) ?? const <Color>[]).take(3))
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
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
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 120),
    this.controller,
    this.emptyRange,
  });

  final List<CalAgendaDay> days;
  final DateTime nowUtc;
  final Set<String> liveKeys;
  final CalTileActions actions;
  final bool showOrg;
  final Widget? header, footer;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  /// Shown under today when nothing else is coming in the whole range.
  final Widget? emptyRange;

  @override
  Widget build(BuildContext context) {
    final upcoming = days.any((d) => !d.today && d.events.isNotEmpty);
    return ListView(
      controller: controller,
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ?header,
        for (final d in days) ...[
          CalAgendaDayCard(day: d, nowUtc: nowUtc, liveKeys: liveKeys, actions: actions, showOrg: showOrg),
          const SizedBox(height: 14),
        ],
        if (!upcoming && emptyRange != null) emptyRange!,
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
  });

  final CalAgendaDay day;
  final DateTime nowUtc;
  final Set<String> liveKeys;
  final CalTileActions actions;
  final bool showOrg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nowWall = AppTime.toZone(nowUtc);
    final count = day.events.where((e) => !e.cancelled).length;
    final rows = <Widget>[];
    for (var i = 0; i <= day.events.length; i++) {
      if (day.today && day.nowAt == i && day.events.isNotEmpty) rows.add(CalNowLine(label: AppTime.time(nowUtc)));
      if (i == day.events.length) break;
      final e = day.events[i];
      if (rows.isNotEmpty && rows.last is! CalNowLine) rows.add(Divider(height: 1, indent: 16, endIndent: 16, color: c.divider));
      rows.add(CalAgendaTile(
        event: e,
        nowUtc: nowUtc,
        live: calIsLive(e, nowUtc, liveKeys: liveKeys),
        joinable: calJoinable(e, nowUtc, liveKeys: liveKeys),
        past: !e.end.isAfter(nowUtc),
        showOrg: showOrg,
        actions: actions,
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 4, 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: day.today ? c.primary : calTint(c, c.primary, 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text('${day.day.day}', style: appText(15, w: FontWeight.w800, c: day.today ? c.onHero : appInk(context, c.primary))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_dayTitle(day.day, nowWall), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.textDark)),
              // the count rides on the date line, beside the title: at the row's END it sat under the assistant's
              // docked edge tab on phones (R3), which docks on that side by default
              Row(children: [
                Flexible(
                  child: Text(_dayDate(day.day, pattern: calDay(day.day).difference(calDay(nowWall)).inDays.abs() <= 1 ? 'EEEE d MMMM' : 'd MMMM y'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textLight)),
                ),
                if (count > 0)
                  Text(t(' · $count ${count == 1 ? 'موعد' : 'مواعيد'}', ' · $count ${count == 1 ? 'event' : 'events'}'),
                      maxLines: 1, style: appText(11.5, w: FontWeight.w600, c: c.textLight)),
              ]),
            ]),
          ),
        ]),
      ),
      for (final p in day.pauses) ...[CalPauseBanner(pause: p), const SizedBox(height: 8)],
      if (day.events.isEmpty)
        CalFreeDay(today: day.today)
      else
        Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.divider.withValues(alpha: 0.7)),
            boxShadow: c.isDark ? null : [BoxShadow(color: c.textDark.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
    ]);
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
        padding: const EdgeInsetsDirectional.fromSTEB(10, 2, 14, 2),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(8)),
            child: Text(label, maxLines: 1, style: appText(10.5, w: FontWeight.w800, c: c.onHero)),
          ),
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
          Expanded(child: Container(height: 1.6, color: c.danger)),
        ]),
      ),
    );
  }
}

class CalFreeDay extends StatelessWidget {
  const CalFreeDay({super.key, this.today = false});
  final bool today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: calTint(c, c.success, 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.success.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Icon(Icons.wb_sunny_rounded, color: appInk(context, c.success), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(today ? t('لا شيء اليوم', 'Nothing today') : t('يوم فارغ', 'A free day'),
                style: appText(14, w: FontWeight.w800, c: c.textDark)),
            Text(t('لا محاضرات ولا اجتماعات — وقتك لك', 'No classes, no meetings — the time is yours'),
                style: appText(12, c: c.textMedium)),
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
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 11),
      decoration: BoxDecoration(
        color: calTint(c, c.warning, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warning.withValues(alpha: 0.30)),
      ),
      child: Row(children: [
        Icon(Icons.pause_circle_rounded, color: ink, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w800, c: c.textDark)),
            Text(
              [
                t('المحاضرات الأسبوعية متوقفة', 'Weekly classes paused'),
                range,
                if ((pause.orgName ?? '').isNotEmpty) pause.orgName!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: appText(11.5, c: c.textMedium),
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
    if (live) CalTag(t('مباشر الآن', 'Live now'), c.danger, icon: Icons.sensors_rounded, solid: true),
    if (!e.cancelled && ch != null && ch.online) CalTag(t('أونلاين هذه المرة', 'Online this time'), c.primary, icon: Icons.videocam_rounded),
    if (!e.cancelled && ch != null && ch.substitute) CalTag(t('مدرس بديل', 'Substitute'), c.warning, icon: Icons.person_pin_rounded),
    if (!e.cancelled && ch != null && ch.mode == 'offline') CalTag(t('حضورياً هذه المرة', 'In person this time'), c.success, icon: Icons.meeting_room_rounded),
    if (e.source == 'timetable' && e.kind == 'lab') CalTag(t('معمل', 'Lab'), calEventColor(c, e)),
    if (e.source == 'exam' && e.kind == 'midterm') CalTag(t('منتصف الفصل', 'Midterm'), c.danger),
    if (e.source == 'exam' && e.kind == 'final') CalTag(t('نهائي', 'Final'), c.danger),
    if (e.isMeeting && e.mode == 'online' && !live) CalTag(t('أونلاين', 'Online'), c.primary, icon: Icons.videocam_rounded),
    if (e.isMeeting && !e.isOwner && e.myStatus != null && e.myStatus != 'owner')
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
    this.showOrg = false,
    this.actions = const CalTileActions(),
  });

  final CalEvent event;
  final DateTime nowUtc;
  final bool live, joinable, past, showOrg;
  final CalTileActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final color = calEventColor(c, e);
    final muted = e.cancelled || e.declined;
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
        ? FilledButton.icon(
            key: ValueKey('cal.join.${e.id}'),
            onPressed: () => actions.onJoin!(e),
            style: FilledButton.styleFrom(
              backgroundColor: live ? c.danger : c.primary,
              foregroundColor: c.onHero,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: Text(t('انضم', 'Join'), style: appText(13, w: FontWeight.w800, c: c.onHero)),
          )
        : null;

    final body = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 66,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (allDay)
              Text(t('طوال اليوم', 'All day'), style: appText(12, w: FontWeight.w800, c: c.textDark))
            else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(AppTime.time(e.start), maxLines: 1, style: appText(13, w: FontWeight.w800, c: muted ? c.textLight : c.textDark)),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(AppTime.time(e.end), maxLines: 1, style: appText(11.5, w: FontWeight.w600, c: c.textLight)),
              ),
            ],
          ]),
        ),
        Container(
          width: 4,
          height: 44,
          margin: const EdgeInsetsDirectional.only(end: 12, top: 1),
          decoration: BoxDecoration(
            color: muted ? c.textLight.withValues(alpha: 0.4) : color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appText(14.5, w: FontWeight.w800, c: muted ? c.textLight : c.textDark).copyWith(
                    decoration: muted ? TextDecoration.lineThrough : null,
                    decorationColor: c.textLight,
                  ),
                ),
              ),
              if (join != null) ...[const SizedBox(width: 8), join],
            ]),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
            ],
            if (tags.isNotEmpty || when != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ...tags,
                if (when != null && !past)
                  Text(when, style: appText(11.5, w: FontWeight.w700, c: live ? appInk(context, c.danger) : c.textLight)),
              ]),
            ],
            if (pendingInvite || answerChange) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
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

    return Semantics(
      button: actions.onTap != null,
      label: '${e.title}, ${AppTime.time(e.start)}',
      child: Material(
        color: live ? calTint(c, c.danger, 0.05) : Colors.transparent,
        child: InkWell(
          onTap: actions.onTap == null ? null : () => actions.onTap!(e),
          child: Opacity(opacity: past && !live ? 0.55 : 1, child: body),
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : calTint(c, color, 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: outline ? c.divider : color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: outline ? c.textMedium : ink),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w800, c: outline ? c.textMedium : ink))),
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 19, color: tone ?? c.textLight),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: appText(14, c: c.textDark, h: 1.35))),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: calTint(c, color, 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(calSourceIcon(e.source), color: appInk(context, color), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(calSourceLabelShort(e).toUpperCase(), style: appText(11, w: FontWeight.w800, c: appInk(context, color)).copyWith(letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(
                e.title,
                style: appText(19, w: FontWeight.w800, c: e.cancelled ? c.textLight : c.textDark, h: 1.25)
                    .copyWith(decoration: e.cancelled ? TextDecoration.lineThrough : null),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ...calTagsOf(context, e, live: live, nowUtc: nowUtc),
          if (when != null) CalTag(when, c.textMedium, icon: Icons.schedule_rounded),
        ]),
        const SizedBox(height: 10),
        line(Icons.event_rounded, '${AppTime.date(e.start, pattern: 'EEEE d MMMM')} · ${AppTime.time(e.start)} – ${AppTime.time(e.end)}'),
        if (e.online && !e.isMeeting)
          line(Icons.videocam_rounded, t('أونلاين', 'Online'))
        else if ((e.location ?? '').isNotEmpty)
          line(Icons.place_rounded, e.location!),
        if ((e.subtitle ?? '').isNotEmpty) line(e.source == 'timetable' ? Icons.person_rounded : Icons.info_outline_rounded, e.subtitle!),
        if ((e.orgName ?? '').isNotEmpty) line(Icons.apartment_rounded, e.orgName!),
        if (ch != null && (ch.online || ch.substitute || ch.cancelled || ch.mode == 'offline')) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: calTint(c, ch.cancelled ? c.danger : (ch.online ? c.primary : c.warning), 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (ch.cancelled ? c.danger : (ch.online ? c.primary : c.warning)).withValues(alpha: 0.28)),
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
                style: appText(14, w: FontWeight.w800, c: c.textDark),
              ),
              if ((ch.note ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text(ch.note!, style: appText(12.5, c: c.textMedium))],
              if (ch.canRespond || ch.canEdit) ...[
                const SizedBox(height: 6),
                Text(t('قبِل ${ch.accept} · رفض ${ch.reject}', '${ch.accept} accepted · ${ch.reject} rejected'), style: appText(12, w: FontWeight.w600, c: c.textMedium)),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
        const SizedBox(height: 18),
        if (joinable && onJoin != null) ...[
          AppPrimaryButton(label: live ? t('انضم الآن', 'Join now') : t('انضم', 'Join'), icon: Icons.videocam_rounded, onPressed: onJoin),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
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
    final base = live ? c.danger : calEventColor(c, e);
    final when = calWhen(e, nowUtc, toWall: AppTime.toZone) ?? AppTime.date(e.start, pattern: 'EEE d MMM');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [base, c.heroEnd(base)],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            boxShadow: [BoxShadow(color: base.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (live) ...[const CalLiveDot(), const SizedBox(width: 6)],
              Expanded(
                child: Text(live ? t('مباشر الآن', 'Live now') : t('التالي', 'Up next'),
                    style: appText(11.5, w: FontWeight.w800, c: c.onHeroMuted).copyWith(letterSpacing: 0.6)),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w700, c: c.onHero))),
            ]),
            const SizedBox(height: 10),
            Text(AppTime.time(e.start), style: appText(26, w: FontWeight.w800, c: c.onHero)),
            const SizedBox(height: 2),
            Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.onHero)),
            const SizedBox(height: 4),
            Text(
              [calSourceLabelShort(e), if ((e.location ?? '').isNotEmpty) e.location!, if ((e.orgName ?? '').isNotEmpty) e.orgName!].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: appText(12, c: c.onHeroMuted),
            ),
          ]),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: calTint(c, c.accent2, 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent2.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.mark_email_unread_rounded, size: 18, color: appInk(context, c.accent2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t('دعوات بانتظار ردك', 'Invitations to answer'), style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
          ),
          Text('${invites.length}', style: appText(13, w: FontWeight.w800, c: appInk(context, c.accent2))),
        ]),
        for (final e in invites.take(3)) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: actions.onTap == null ? null : () => actions.onTap!(e),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.textDark)),
              Text('${AppTime.date(e.start, pattern: 'EEE d MMM')} · ${AppTime.time(e.start)}', style: appText(11.5, c: c.textMedium)),
            ]),
          ),
          if (actions.onRsvp != null) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _MiniAction(label: t('قبول', 'Accept'), icon: Icons.check_rounded, color: c.success, onTap: () => actions.onRsvp!(e, 'accepted')),
              _MiniAction(label: t('اعتذار', 'Decline'), icon: Icons.close_rounded, color: c.danger, outline: true, onTap: () => actions.onRsvp!(e, 'declined')),
            ]),
          ],
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Loading
// ═════════════════════════════════════════════════════════════════════════════

class CalScheduleSkeleton extends StatelessWidget {
  const CalScheduleSkeleton({super.key, required this.view});
  final CalView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (view == CalView.agenda) {
      Widget day(int rows) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                AppSkeletonBox(width: 34, height: 34, radius: 11),
                SizedBox(width: 10),
                AppSkeletonBox(width: 120, height: 14),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.divider.withValues(alpha: 0.7))),
                child: Column(children: [
                  for (var i = 0; i < rows; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 16),
                      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          AppSkeletonBox(width: 48, height: 12),
                          SizedBox(height: 6),
                          AppSkeletonBox(width: 36, height: 10),
                        ]),
                        SizedBox(width: 18),
                        AppSkeletonBox(width: 4, height: 40, radius: 4),
                        SizedBox(width: 12),
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
              ),
            ]),
          );
      return AppShimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [day(3), day(2), day(2)],
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
