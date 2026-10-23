// lib/features/org/org_timetable_time.dart — picking a wall-clock time in the timetable feature.
//
// Periods, sittings and special periods are stored as the organization's "HH:MM" (never converted); they are shown
// and picked in the effective 12h / 24h format of AppTime (org setting → platform default → 12h).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../admin/admin_common.dart';
import 'org_ui.dart';

String hhmmOf(TimeOfDay x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';

TimeOfDay? timeOfDayOf(String? hhmm) {
  final p = (hhmm ?? '').split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0].trim()), m = int.tryParse(p[1].trim().padRight(2, '0').substring(0, 2));
  return h == null || m == null ? null : TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

/// The platform time picker in the effective 12h / 24h format → "HH:MM", or null when dismissed.
Future<String?> pickClock(BuildContext context, String? initial, {String? help}) async {
  final x = await showTimePicker(
    context: context,
    helpText: help,
    initialTime: timeOfDayOf(initial) ?? const TimeOfDay(hour: 9, minute: 0),
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: AppTime.use24h), child: child!),
  );
  return x == null ? null : hhmmOf(x);
}

/// A tappable field that shows a "HH:MM" value as "8:30 AM" (or "08:30") and opens [pickClock].
class ClockField extends StatelessWidget {
  const ClockField({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = AppTime.clock(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: !enabled
            ? null
            : () async {
                final v = await pickClock(context, value, help: label);
                if (v != null) onChanged(v);
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: c.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            prefixIcon: Icon(Icons.schedule_rounded, color: c.primary, size: 20),
            isDense: true,
          ),
          child: Text(shown.isEmpty ? t('اختر الوقت', 'Pick a time') : shown,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w700, color: shown.isEmpty ? c.textLight : c.textDark)),
        ),
      ),
    );
  }
}
