// features/courses/teacher/wizard/weekly_slot_sheet.dart — the "add a weekly appointment" sheet of the course form.
library;

import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart' show kDayOrder, kDayLabels;

class LocalAddScheduleSheet extends StatefulWidget {
  final Set<String> existingDays;
  final void Function(String day, String startTime, String endTime) onAdd;

  const LocalAddScheduleSheet({
    required this.existingDays,
    required this.onAdd,
  });

  @override
  State<LocalAddScheduleSheet> createState() => LocalAddScheduleSheetState();
}

class LocalAddScheduleSheetState extends State<LocalAddScheduleSheet> {
  static final List<(String, String)> _days = kDayOrder
      .map((d) => (d, kDayLabels[d] ?? d))
      .toList();

  String _day = kDayOrder.first;
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 12, minute: 0);

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid =>
      _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;

  Future<void> _pick(bool isStart) async {
    final p = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (p == null || !mounted) return;
    setState(() => isStart ? _start = p : _end = p);
  }

  Future<void> _submit() async {
    if (!_valid) return;

    if (widget.existingDays.contains(_day)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'duplicate-schedule'.tr,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'same-day-schedule-exists'.tr,
              style: TextStyle(fontFamily: AppFonts.display),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'cancel'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.textMedium,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'add'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }

    widget.onAdd(_day, _fmt(_start), _fmt(_end));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
    title: 'add-weekly-appointment'.tr,
    children: [
          Text(
            'today'.tr,
            style: AppType.label(context),
          ),
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            height: AppTouch.min,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
              itemBuilder: (_, i) {
                final (v, l) = _days[i];
                final sel = _day == v;
                return GestureDetector(
                  onTap: () => setState(() => _day = v),
                  child: AnimatedContainer(
                    duration: AppMotion.of(context).fast,
                    curve: AppEase.out,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    decoration: BoxDecoration(
                      color: sel ? context.colors.primary : context.colors.inputBg,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: sel ? context.colors.primary : context.colors.divider,
                        width: AppBorder.hairline,
                      ),
                    ),
                    child: Text(
                      l,
                      style: context.colors.label.copyWith(
                        color: sel ? context.colors.onHero : context.colors.textMedium,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'start-time'.tr,
                  time: _start,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _TimeField(
                  label: 'end-time'.tr,
                  time: _end,
                  onTap: () => _pick(false),
                  hasError: !_valid,
                ),
              ),
            ],
          ),
          if (!_valid) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'end-time-must-be-after-start-time'.tr,
              style: context.colors.caption.copyWith(
                color: context.colors.danger,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          AppButton.primary(
            label: 'add-appointment'.tr,
            expand: true,
            onPressed: _valid ? _submit : null,
          ),
    ],
  );
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool hasError;

  const _TimeField({
    required this.label,
    required this.time,
    required this.onTap,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFieldLabel(label),
        Material(
          color: c.inputBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: BorderSide(
              color: hasError ? c.danger : c.divider,
              width: hasError ? AppBorder.strong : AppBorder.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: AppIconSize.md,
                      color: hasError ? c.danger : c.textMedium,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          AppTime.clockMinutes(time.hour * 60 + time.minute),
                          style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
