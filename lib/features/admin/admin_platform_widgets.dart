// lib/features/admin/admin_platform_widgets.dart
//
// Pieces shared by the super-admin "Platform settings" page and the organization admin's "Time & features" page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:timezone/timezone.dart' as tz;

import 'admin_common.dart' show t;

const _regionNames = [
  ('مصر', 'Egypt'),
  ('السعودية', 'Saudi Arabia'),
  ('الإمارات', 'UAE'),
  ('دول عربية', 'Arab countries'),
  ('دول أخرى', 'Other'),
];

/// Timezone (ordered Egypt → KSA → UAE → Arab world → others) + 12h / 24h, with a live preview.
/// [zone] / [timeFormat] null = "follow the default" (only when [inheritLabel] is given).
class RegionEditor extends StatelessWidget {
  const RegionEditor({
    super.key,
    required this.zone,
    required this.timeFormat,
    required this.onZone,
    required this.onFormat,
    this.inheritLabel,
    this.inheritedZone,
    this.inheritedFormat,
    this.enabled = true,
  });

  final String? zone;
  final String? timeFormat;
  final ValueChanged<String?> onZone;
  final ValueChanged<String?> onFormat;
  final String? inheritLabel; // e.g. "Platform default"
  final String? inheritedZone;
  final String? inheritedFormat;
  final bool enabled;

  String _zoneText(AppZone z) => '${z.label}  ·  ${t(_regionNames[z.region].$1, _regionNames[z.region].$2)}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effZone = zone ?? inheritedZone ?? AppTime.fallbackZone;
    final eff24 = (timeFormat ?? inheritedFormat ?? '12h') == '24h';
    final now = DateTime.now().toUtc();
    final options = <String, String>{for (final z in AppTime.zones) z.id: _zoneText(z)};
    if (zone != null && !options.containsKey(zone)) options[zone!] = zone!;
    Widget fmtChip(String? v, String label) => AppChoiceChip(
          label: label,
          selected: timeFormat == v,
          onTap: enabled ? () => onFormat(v) : () {},
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      IgnorePointer(
        ignoring: !enabled,
        child: AppPicker<String>(
          label: t('المنطقة الزمنية', 'Timezone'),
          icon: Icons.public_rounded,
          value: zone,
          options: options,
          allowNone: inheritLabel != null,
          noneLabel: inheritLabel == null
              ? null
              : '$inheritLabel · ${AppTime.zoneInfo(inheritedZone ?? AppTime.fallbackZone).label}',
          onChanged: onZone,
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(t('نظام الوقت', 'Clock'), style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (inheritLabel != null) fmtChip(null, '$inheritLabel (${(inheritedFormat ?? '12h') == '24h' ? '24' : '12'})'),
        fmtChip('12h', t('12 ساعة (ص / م)', '12-hour (AM / PM)')),
        fmtChip('24h', t('24 ساعة', '24-hour')),
      ]),
      const SizedBox(height: AppSpace.sm),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.primary.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Icon(Icons.schedule_rounded, color: c.primary, size: 20),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              '${t('الوقت الآن', 'Now')}: ${_preview(now, effZone, eff24)}  ·  ${AppTime.zoneInfo(effZone).label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// Preview without touching the global AppTime settings.
  static String _preview(DateTime utc, String zone, bool h24) {
    AppTime.toZone(utc); // makes sure the timezone database is loaded
    DateTime wall;
    try {
      wall = tz.TZDateTime.from(utc, tz.getLocation(zone));
    } catch (_) {
      wall = utc.toLocal();
    }
    return AppTime.clockMinutes(wall.hour * 60 + wall.minute, h24: h24);
  }
}

/// Small rounded section header with an icon (Organizations · Time & region · Features).
class PlatformSectionHeader extends StatelessWidget {
  const PlatformSectionHeader({super.key, required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.xs),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(icon, color: c.primary, size: 20),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
            if (subtitle != null)
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
      ]),
    );
  }
}
