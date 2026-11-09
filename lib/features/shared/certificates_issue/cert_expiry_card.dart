// lib/features/shared/certificates_issue/cert_expiry_card.dart
//
// The issuer's expiry date (D-420): off by default, because a certificate does not expire unless someone says so. A
// day is chosen; it counts until the end of that day in the platform or organization timezone.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/app_time.dart';
import '../../../design/app_kit.dart';

/// The instant sent to the server for a chosen day.
String certExpiryWire(DateTime day) =>
    AppTime.fromZone(DateTime(day.year, day.month, day.day, 23, 59, 59)).toUtc().toIso8601String();

class CertExpiryCard extends StatelessWidget {
  const CertExpiryCard({super.key, required this.value, required this.onChanged, this.pick});

  /// The chosen day (wall date), null = does not expire.
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Tests: replaces the date picker.
  final Future<DateTime?> Function(BuildContext context, DateTime initial)? pick;

  static Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 50),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final initial = value ?? DateTime.now().add(const Duration(days: 365));
    final chosen = await (pick ?? _pickDate)(context, initial);
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = value != null;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
          value: on,
          title: 'cv_expiry_toggle'.tr,
          subtitle: on ? null : 'cv_expiry_off_sub'.tr,
          onChanged: (v) => v ? _choose(context) : onChanged(null),
        ),
        if (on) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('cv.expiry.pick'),
              onPressed: () => _choose(context),
              style: TextButton.styleFrom(foregroundColor: c.primary, minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.event_rounded, size: AppIconSize.md),
              label: Text(AppTime.date(AppTime.fromZone(DateTime(value!.year, value!.month, value!.day, 12)))),
            ),
          ),
        ],
      ]),
    );
  }
}
