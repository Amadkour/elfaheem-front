// features/courses/teacher/wizard/weekly_slot_sheet.dart — "add a weekly slot" (Tea1Wizard schedadd): the day, from and
// to, one note on what repeats, and an inline warning when that day already has a slot. It used to ask again in a
// dialog; now the warning is on the sheet and the button says "Yes, add it". Plain values in, one callback out, so
// the layout harness can pump it; the weekday names and the wire scale are the recurrence code's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart'
    show recurrenceDayName, recurrenceTimeParse, recurrenceTimeWire, recurrenceWeekOrder;
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart' show wizardRange;
import 'package:flutter_education_app/features/data_lab/data_lab_widgets.dart' show DlBanner;
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart' show kDayOrder;

/// A weekly slot as the form keeps it: the server's day key ('sunday'), "HH:MM" start and end.
typedef WeeklySlotValue = ({String day, String start, String end});

/// The default length of a new slot, in minutes.
const int kWeeklySlotMinutes = 50;

/// A length in minutes, "50 minutes".
String weeklySlotMinutesText(int n) => countText(n,
    ar1: 'دقيقة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes');

class LocalAddScheduleSheet extends StatefulWidget {
  const LocalAddScheduleSheet({super.key, required this.existing, required this.onAdd, this.initial});

  /// The slots already on the course (not the one being edited).
  final List<WeeklySlotValue> existing;

  /// Editing: the slot's current values.
  final WeeklySlotValue? initial;
  final void Function(String day, String startTime, String endTime) onAdd;

  @override
  State<LocalAddScheduleSheet> createState() => LocalAddScheduleSheetState();
}

class LocalAddScheduleSheetState extends State<LocalAddScheduleSheet> {
  late String _day;
  late int _start; // minutes after midnight
  late int _end;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _day = i?.day ?? kDayOrder.first;
    _start = (i == null ? null : recurrenceTimeParse(i.start)) ?? 16 * 60;
    _end = (i == null ? null : recurrenceTimeParse(i.end)) ?? _start + kWeeklySlotMinutes;
  }

  bool get _valid => _end > _start;

  WeeklySlotValue? get _sameDay {
    for (final s in widget.existing) {
      if (s.day == _day) return s;
    }
    return null;
  }

  Future<void> _pick(bool isStart) async {
    final now = isStart ? _start : _end;
    final p = await showTimePicker(context: context, initialTime: TimeOfDay(hour: now ~/ 60 % 24, minute: now % 60));
    if (p == null || !mounted) return;
    final m = p.hour * 60 + p.minute;
    setState(() {
      if (isStart) {
        final length = _end - _start;
        _start = m;
        if (length > 0) _end = m + length; // moving the start keeps the length
      } else {
        _end = m;
      }
    });
  }

  void _submit() {
    if (!_valid) return;
    widget.onAdd(_day, recurrenceTimeWire(_start), recurrenceTimeWire(_end));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final same = _sameDay;
    final dayName = recurrenceDayName(kDayOrder.indexOf(_day));
    return AppSheetContent(
      title: 't1_wz_sheet_title'.tr,
      icon: Icons.event_repeat_rounded,
      children: [
        AppFieldLabel('t1_wz_day'.tr),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final w in recurrenceWeekOrder())
            AppChip(label: recurrenceDayName(w), selected: kDayOrder[w] == _day, onTap: () => setState(() => _day = kDayOrder[w])),
        ]),
        const SizedBox(height: AppSpace.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _TimeWell(label: 't1_wz_from'.tr, minutes: _start, onTap: () => _pick(true))),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: _TimeWell(label: 't1_wz_to'.tr, minutes: _end, onTap: () => _pick(false), hasError: !_valid)),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (!_valid)
          Text('end-time-must-be-after-start-time'.tr, style: AppType.meta(context).copyWith(color: c.danger))
        else
          Text('${'t1_wz_len_is'.tr} ${weeklySlotMinutesText(_end - _start)}${ar ? '،' : ','} ${'t1_wz_repeats'.tr} $dayName',
              style: AppType.meta(context)),
        if (same != null) ...[
          const SizedBox(height: AppSpace.md),
          DlBanner(
            key: const ValueKey('wizard.slot.same_day'),
            icon: Icons.warning_amber_rounded,
            color: c.warning,
            text: '${'t1_wz_same_day_a'.tr} $dayName ${wizardRange(same.start, same.end)}. ${'t1_wz_same_day_b'.tr}',
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(children: [
          Flexible(child: AppButton.secondary(key: const ValueKey('wizard.slot.cancel'), label: 'cancel'.tr, onPressed: () => Navigator.pop(context))),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 2,
            child: AppButton.primary(
              key: const ValueKey('wizard.slot.add'),
              label: same != null ? 't1_wz_yes_add'.tr : (widget.initial != null ? 't1_wz_save_slot'.tr : 't1_wz_add_slot'.tr),
              icon: Icons.add_rounded,
              expand: true,
              onPressed: _valid ? _submit : null,
            ),
          ),
        ]),
      ],
    );
  }
}

class _TimeWell extends StatelessWidget {
  const _TimeWell({required this.label, required this.minutes, required this.onTap, this.hasError = false});

  final String label;
  final int minutes;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppFieldLabel(label),
      Material(
        color: c.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
          side: BorderSide(color: hasError ? c.danger : c.divider, width: hasError ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(children: [
                Icon(Icons.access_time_rounded, size: AppIconSize.md, color: hasError ? c.danger : c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(AppTime.clockMinutes(minutes), style: AppType.figure(context)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
