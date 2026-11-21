// lib/features/calendar/recurrence/recurrence_picker.dart — the Repeat section of a meeting (and of the packages
// wizard): how it repeats, which weekdays, the step, start and end, the time, skipped weekdays and dates, and the
// live summary sentence (describeRule). Controlled: [RecurrencePicker.rule] in, [onChanged] out; null = "Does not
// repeat". Hidden by the kill switch `calendar.recurring` (D-1574).
//
//   RecurrencePicker          the section (plain values: pumped by the layout harness)
//   RecurrenceReminderField   "Remind me n minutes before" (default 15), for a single meeting too
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

/// The Repeat section. [start] is the first date and the default clock when a repeat is switched on (wall clock).
/// [withDateTime] false: the host form owns the first date and the from–to (the meeting form), so the section
/// shows neither.
class RecurrencePicker extends StatefulWidget {
  const RecurrencePicker({
    super.key,
    required this.rule,
    required this.onChanged,
    required this.start,
    this.end,
    this.withDateTime = true,
  });

  final RecurrenceRule? rule;
  final ValueChanged<RecurrenceRule?> onChanged;
  final DateTime start;
  final DateTime? end;
  final bool withDateTime;

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  /// The last rule, so "Does not repeat" and back keeps what was picked.
  RecurrenceRule? _last;

  RecurrenceRule? get _r => widget.rule;

  void _set(RecurrenceRule? r) {
    if (r != null) _last = r;
    widget.onChanged(r);
  }

  String get _choice => switch (_r?.freq) {
        null => 'none',
        RecurrenceFreq.daily => 'daily',
        RecurrenceFreq.weekly => 'weekly',
        RecurrenceFreq.custom => 'custom',
      };

  void _pickFreq(String? v) {
    if (v == null || v == _choice) return;
    if (v == 'none') return _set(null);
    final freq = RecurrenceFreq.values.firstWhere((f) => f.name == v);
    final base = _r ?? _last ?? RecurrenceRule.from(widget.start, end: widget.end, freq: freq);
    final firstDay = [recurrenceWeekdayOf(base.startDate)];
    _set(switch (freq) {
      RecurrenceFreq.daily => base.copyWith(freq: freq, interval: 1, weekdays: const []),
      RecurrenceFreq.weekly =>
        base.copyWith(freq: freq, interval: 1, weekdays: base.weekdays.isEmpty ? firstDay : base.weekdays, skipWeekdays: const []),
      RecurrenceFreq.custom => base.copyWith(freq: freq, interval: base.interval < 2 ? 2 : base.interval),
    });
  }

  List<int> _toggle(List<int> list, int d) => list.contains(d) ? (List.of(list)..remove(d)) : [...list, d];

  Future<DateTime?> _date(DateTime initial, {DateTime? first}) => showDatePicker(
        context: context,
        initialDate: first != null && initial.isBefore(first) ? first : initial,
        firstDate: first ?? DateTime(initial.year - 1),
        lastDate: DateTime(initial.year + 3),
      );

  Future<int?> _time(int minutes) async {
    final tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    return tod == null ? null : tod.hour * 60 + tod.minute;
  }

  @override
  Widget build(BuildContext context) => ParentComponent(featureKey: kRecurringFeatureKey, child: _section(context));

  Widget _section(BuildContext context) {
    final c = context.colors;
    final r = _r;
    return Column(
      key: const ValueKey('recurrence.picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppDropdown<String>(
          key: const ValueKey('recurrence.freq'),
          value: _choice,
          decoration: InputDecoration(labelText: 'cal_recur_repeat'.tr, prefixIcon: const Icon(Icons.repeat_rounded)),
          items: [
            DropdownMenuItem(value: 'none', child: Text('cal_recur_none'.tr)),
            DropdownMenuItem(value: 'daily', child: Text('cal_recur_daily'.tr)),
            DropdownMenuItem(value: 'weekly', child: Text('cal_recur_weekly'.tr)),
            DropdownMenuItem(value: 'custom', child: Text('cal_recur_custom'.tr)),
          ],
          onChanged: _pickFreq,
        ),
        if (r != null) ...[
          if (r.freq == RecurrenceFreq.custom) ...[
            const SizedBox(height: AppSpace.sm),
            _intervalRow(context, r),
          ],
          if (r.unit == RecurrenceUnit.weeks) ...[
            const SizedBox(height: AppSpace.sm),
            AppFieldLabel('cal_recur_on_days'.tr),
            _WeekdayChips(
              keyPrefix: 'recurrence.day',
              selected: r.weekdays,
              onToggle: (d) {
                final next = _toggle(r.weekdays, d);
                if (next.isNotEmpty) _set(r.copyWith(weekdays: next)); // a weekly rule keeps one day at least
              },
            ),
          ] else ...[
            const SizedBox(height: AppSpace.sm),
            AppFieldLabel('cal_recur_skip_days'.tr),
            _WeekdayChips(
              keyPrefix: 'recurrence.skip_day',
              selected: r.skipWeekdays,
              onToggle: (d) {
                final next = _toggle(r.skipWeekdays, d);
                if (next.length < 7) _set(r.copyWith(skipWeekdays: next)); // never every day skipped
              },
            ),
          ],
          if (widget.withDateTime) ...[
            const SizedBox(height: AppSpace.sm),
            _Box(
              key: const ValueKey('recurrence.start_date'),
              icon: Icons.event_rounded,
              label: 'cal_recur_starts'.tr,
              value: AppTime.wall(r.startDate, pattern: 'EEE d MMM y'),
              onTap: () async {
                final d = await _date(r.startDate);
                if (d == null) return;
                final end = r.endDate;
                _set(end != null && end.isBefore(d) ? r.copyWith(startDate: d, clearEnd: true) : r.copyWith(startDate: d));
              },
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          AppDropdown<String>(
            key: const ValueKey('recurrence.ends'),
            value: r.endDate != null ? 'date' : (r.count != null ? 'count' : 'never'),
            decoration: InputDecoration(labelText: 'cal_recur_ends'.tr, prefixIcon: const Icon(Icons.flag_rounded)),
            items: [
              DropdownMenuItem(value: 'never', child: Text('cal_recur_no_end'.tr)),
              DropdownMenuItem(value: 'date', child: Text('cal_recur_end_on'.tr)),
              DropdownMenuItem(value: 'count', child: Text('cal_recur_end_after'.tr)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              if (v == 'never') return _set(r.copyWith(clearEnd: true, clearCount: true));
              if (v == 'count') return _set(r.copyWith(clearEnd: true, count: r.count ?? 10));
              final d = await _date(r.startDate.add(const Duration(days: 30)), first: r.startDate);
              if (d != null) _set(r.copyWith(endDate: d, clearCount: true));
            },
          ),
          if (r.count != null && r.endDate == null) ...[
            const SizedBox(height: AppSpace.xs),
            _countRow(context, r),
          ],
          if (r.endDate != null) ...[
            const SizedBox(height: AppSpace.xs),
            _Box(
              key: const ValueKey('recurrence.end_date'),
              icon: Icons.event_available_rounded,
              label: 'cal_recur_end_date'.tr,
              value: AppTime.wall(r.endDate!, pattern: 'EEE d MMM y'),
              onTap: () async {
                final d = await _date(r.endDate!, first: r.startDate);
                if (d != null) _set(r.copyWith(endDate: d));
              },
            ),
          ],
          if (widget.withDateTime) ...[
            const SizedBox(height: AppSpace.xs),
            AppSwitchTile(
              key: const ValueKey('recurrence.any_time'),
              title: 'cal_recur_any_time'.tr,
              icon: Icons.all_inclusive_rounded,
              value: r.allDay,
              onChanged: (v) => _set(r.copyWith(
                  allDay: v,
                  startTime: r.startTime ?? widget.start.hour * 60 + widget.start.minute,
                  endTime: r.endTime ?? (widget.start.hour * 60 + widget.start.minute + 60) % 1440)),
            ),
            if (!r.allDay)
              Row(children: [
                Expanded(
                  child: _Box(
                    key: const ValueKey('recurrence.from'),
                    icon: Icons.schedule_rounded,
                    label: 'cal_recur_from'.tr,
                    value: AppTime.clockMinutes(r.startTime ?? 0),
                    onTap: () async {
                      final m = await _time(r.startTime ?? 0);
                      if (m == null) return;
                      final len = ((r.endTime ?? m + 60) - (r.startTime ?? m)).clamp(15, 1440);
                      _set(r.copyWith(startTime: m, endTime: (m + len) % 1440));
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: _Box(
                    key: const ValueKey('recurrence.to'),
                    icon: Icons.schedule_rounded,
                    label: 'cal_recur_to'.tr,
                    value: AppTime.clockMinutes(r.endTime ?? 0),
                    onTap: () async {
                      final m = await _time(r.endTime ?? 0);
                      if (m != null) _set(r.copyWith(endTime: m));
                    },
                  ),
                ),
              ]),
          ],
          const SizedBox(height: AppSpace.sm),
          AppFieldLabel('cal_recur_skip_dates'.tr),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final d in r.skipDates)
              InputChip(
                key: ValueKey('recurrence.skip_date.${recurrenceDateWire(d)}'),
                label: Text(AppTime.wall(d, pattern: 'EEE d MMM'), style: appText(12, c: c.textDark)),
                deleteButtonTooltipMessage: 'cal_recur_remove_date'.tr,
                onDeleted: () => _set(r.copyWith(skipDates: [
                  for (final x in r.skipDates)
                    if (recurrenceDateWire(x) != recurrenceDateWire(d)) x,
                ])),
              ),
            ActionChip(
              key: const ValueKey('recurrence.add_skip_date'),
              avatar: Icon(Icons.add_rounded, size: AppIconSize.sm, color: c.primary),
              label: Text('cal_recur_add_date'.tr, style: appText(12, w: FontWeight.w700, c: c.primary)),
              onPressed: () async {
                final d = await _date(r.startDate.add(const Duration(days: 7)), first: r.startDate);
                if (d == null || r.skipDates.any((x) => recurrenceDateWire(x) == recurrenceDateWire(d))) return;
                _set(r.copyWith(skipDates: [...r.skipDates, d]..sort()));
              },
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('recurrence.summary'),
            icon: Icons.repeat_rounded,
            color: c.primary,
            text: describeRule(r, AppConfig.lang),
          ),
        ],
      ],
    );
  }

  /// "After [–] n [+] times" (1..365).
  Widget _countRow(BuildContext context, RecurrenceRule r) {
    final c = context.colors;
    final n = r.count ?? 1;
    return Row(children: [
      Flexible(child: Text('cal_recur_after'.tr, style: appText(14, w: FontWeight.w600, c: c.textDark))),
      IconButton(
        key: const ValueKey('recurrence.count_down'),
        tooltip: 'cal_recur_less'.tr,
        onPressed: n > 1 ? () => _set(r.copyWith(count: n - 1)) : null,
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
      Text('$n', key: const ValueKey('recurrence.count'), style: appText(16, w: FontWeight.w800, c: c.textDark)),
      IconButton(
        key: const ValueKey('recurrence.count_up'),
        tooltip: 'cal_recur_more'.tr,
        onPressed: n < 365 ? () => _set(r.copyWith(count: n + 1)) : null,
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
      Flexible(
        child: Text(countText(n, ar1: 'مرة', ar2: 'مرتين', arFew: 'مرات', arMany: 'مرة', en1: 'time', en: 'times'),
            style: appText(14, c: c.textMedium)),
      ),
    ]);
  }

  Widget _intervalRow(BuildContext context, RecurrenceRule r) {
    final c = context.colors;
    final n = r.interval;
    // the step on one line, its unit under it: a narrow phone at a large text size keeps both readable
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
      Flexible(child: Text('cal_recur_every'.tr, style: appText(14, w: FontWeight.w600, c: c.textDark))),
      IconButton(
        key: const ValueKey('recurrence.interval_down'),
        tooltip: 'cal_recur_less'.tr,
        onPressed: n > 1 ? () => _set(r.copyWith(interval: n - 1)) : null,
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
      Text('$n', key: const ValueKey('recurrence.interval'), style: appText(16, w: FontWeight.w800, c: c.textDark)),
      IconButton(
        key: const ValueKey('recurrence.interval_up'),
        tooltip: 'cal_recur_more'.tr,
        onPressed: n < 30 ? () => _set(r.copyWith(interval: n + 1)) : null,
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
      ]),
      AppDropdown<RecurrenceUnit>(
          key: const ValueKey('recurrence.unit'),
          value: r.unit,
          items: [
            DropdownMenuItem(
                value: RecurrenceUnit.days,
                child: Text(countText(n, ar1: 'يوم', ar2: 'يومين', arFew: 'أيام', arMany: 'يومًا', en1: 'day', en: 'days'))),
            DropdownMenuItem(
                value: RecurrenceUnit.weeks,
                child: Text(countText(n, ar1: 'أسبوع', ar2: 'أسبوعين', arFew: 'أسابيع', arMany: 'أسبوعًا', en1: 'week', en: 'weeks'))),
          ],
          onChanged: (u) {
            if (u == null || u == r.unit) return;
            _set(u == RecurrenceUnit.weeks
                ? r.copyWith(weekdays: [recurrenceWeekdayOf(r.startDate)], skipWeekdays: const [])
                : r.copyWith(weekdays: const []));
          },
        ),
    ]);
  }
}

/// The seven weekday chips in the locale's order (Saturday first in Arabic).
class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.keyPrefix, required this.selected, required this.onToggle});
  final String keyPrefix;
  final List<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final d in recurrenceWeekOrder())
          AppChoiceChip(
            key: ValueKey('$keyPrefix.$d'),
            label: recurrenceDayName(d),
            selected: selected.contains(d),
            onTap: () => onToggle(d),
          ),
      ]);
}

/// A tappable value well (a date, a clock) in the field look.
class _Box extends StatelessWidget {
  const _Box({super.key, required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.inputBg,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(children: [
              Icon(icon, size: AppIconSize.md, color: c.primary),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, c: c.textLight)),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "n minutes before" in the open language (0 = at the start).
String recurrenceReminderLabel(int minutes) {
  if (minutes <= 0) return 'cal_recur_remind_at_start'.tr;
  if (minutes % 1440 == 0) {
    return countText(minutes ~/ 1440,
        ar1: 'قبلها بيوم', ar2: 'قبلها بيومين', arFew: 'قبلها بـ{n} أيام', arMany: 'قبلها بـ{n} يومًا',
        en1: '1 day before', en: '{n} days before');
  }
  if (minutes % 60 == 0) {
    return countText(minutes ~/ 60,
        ar1: 'قبلها بساعة', ar2: 'قبلها بساعتين', arFew: 'قبلها بـ{n} ساعات', arMany: 'قبلها بـ{n} ساعة',
        en1: '1 hour before', en: '{n} hours before');
  }
  return countText(minutes,
      ar1: 'قبلها بدقيقة', ar2: 'قبلها بدقيقتين', arFew: 'قبلها بـ{n} دقائق', arMany: 'قبلها بـ{n} دقيقة',
      en1: '1 minute before', en: '{n} minutes before');
}

/// The reminder lead time of a meeting or a series (default 15 minutes).
class RecurrenceReminderField extends StatelessWidget {
  const RecurrenceReminderField({super.key, required this.minutes, required this.onChanged});
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = {...recurrenceReminderChoices, minutes}.toList()..sort();
    return AppDropdown<int>(
      key: const ValueKey('recurrence.reminder'),
      value: minutes,
      decoration: InputDecoration(labelText: 'cal_recur_reminder'.tr, prefixIcon: const Icon(Icons.notifications_active_rounded)),
      items: [for (final m in choices) DropdownMenuItem(value: m, child: Text(recurrenceReminderLabel(m)))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
