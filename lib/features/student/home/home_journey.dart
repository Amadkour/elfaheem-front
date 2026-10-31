// lib/features/student/home/home_journey.dart
//
// The student home's ONE roadmap card (D-120): "Continue your journey in <field>" · the next step only · a light
// bar of the path done. Read from /me/home's `journey` (no call of its own); no clear field → no card at all.
// Card surface + hairline like the rest of the calm home (D-102); the attendance entry's light sweep (AppShineBand)
// crosses it slowly every few seconds, parked by Reduce motion. Tap → the whole path (JourneyPage).
//
// When it shows ([homeJourney]): the personal context only (never in Organization mode, never for an org-admin /
// org-staff login), the switches `roadmap` / `roadmap.journey` on, and a clear field — the server's block is null
// only when the student has no roadmap course, no completed course and no chosen interest yet (or turned
// recommendations off). That "no data" state is the one intentional reason the card is absent.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_shine.dart';
import '../../shared/roadmap/roadmap_api.dart';

/// The card's data from /me/home's raw `journey` block, or null when no card is drawn: not the personal context
/// ([roadmapOrgAccount]: Organization mode or an organization login), a switch off, or no clear interest yet.
Journey? homeJourney(Map<String, dynamic>? raw, {String? role}) {
  if (raw == null || roadmapOff(kRoadmapJourneyKey) || roadmapOrgAccount(role)) return null;
  return Journey.fromJson(raw);
}

class HomeJourneyCard extends StatelessWidget {
  const HomeJourneyCard({super.key, required this.journey, this.onTap});

  final Journey journey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final j = journey;
    return Semantics(
      button: onTap != null,
      label: '${j.title}. ${j.nextLine}. ${j.doneLine}',
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: AppShineBand(
                  color: c.primary.withValues(alpha: 0.07),
                  period: const Duration(seconds: 6),
                  sweep: 0.3,
                  width: 28,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.route_rounded, size: 22, color: appInk(context, c.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark, h: 1.3)),
                          const SizedBox(height: 2),
                          Text(j.nextLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w400, c: c.textMedium)),
                          const SizedBox(height: 8),
                          AppProgressBar(value: j.fraction * 100, height: 4, color: appInk(context, c.primary)),
                          Text(j.doneLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: c.textMedium)),
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, size: 22, color: c.textLight),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
