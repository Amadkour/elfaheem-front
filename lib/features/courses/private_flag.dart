// lib/features/courses/private_flag.dart
//
// "Private" — a small pill on the course hero (and anywhere a private course is named): the danger tint laid over
// the surface it sits on (the hero block, else the card), a lock and the word in the tint's ink. No fill-and-glow:
// a white label on the red fill read as an alarm (Warm Editorial, D-613).
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppBlock, AppSpace, AppRadius, AppType, AppIconSize, appInkOn, appTintOn;

class PrivateFlag extends StatelessWidget {
  const PrivateFlag({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = appTintOn(context, c.danger, surface: AppBlock.colorsOf(context).surface);
    final ink = appInkOn(context, c.danger, fill);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpace.lg + AppSpace.xxs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - 2, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(
              label ?? 'private'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
