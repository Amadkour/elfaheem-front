// lib/features/student/home/home_journey.dart
//
// The student home's ONE roadmap card (D-120, redesigned D-309): "Your learning path" · "Continue your journey in
// <field>" · the next step (thumbnail, name, where the student is in it) · the path as segments (done / here / next)
// · "2 of 3 done" · ONE tonal "Continue" / "Start" button that opens the next course straight away. The card itself
// opens the whole path (JourneyPage), drawn at once from the same block. Read from /me/home's `journey` (no call of
// its own); a paper card on a warm hairline like the rest of the calm home (D-102 / D-612), its title in the editorial
// section face. No light sweep any more: the home's one memorable element is the "Continue learning" block above it.
//
// When it shows ([homeJourney]): the personal context only (never in Organization mode, never for an org-admin /
// org-staff login), the switches `roadmap` / `roadmap.journey` on, and a clear field.
//
// No journey yet (D-309): the server names `journey_hint: "pick_interests"` when choosing interests would give the
// student one (personal context, switch on, recommendations not turned off, no interest chosen). Then the same slot
// holds [HomeJourneyInvite] — "Plan your learning path" · one "Pick your interests" button (the interests sheet) —
// so a new student finds the roadmap too. Without the hint (an older server, recommendations off) the slot is empty.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart' show JourneyTrack, journeyActionLabel, journeyStepState;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';

/// The card's data from /me/home's raw `journey` block, or null when no card is drawn: not the personal context
/// ([roadmapOrgAccount]: Organization mode or an organization login), a switch off, or no clear interest yet.
Journey? homeJourney(Map<String, dynamic>? raw, {String? role}) {
  if (raw == null || roadmapOff(kRoadmapJourneyKey) || roadmapOrgAccount(role)) return null;
  return Journey.fromJson(raw);
}

/// Whether the slot invites the student to pick interests (no journey yet, /me/home's `journey_hint`).
bool homeJourneyInvite(String? hint, {String? role}) =>
    hint == 'pick_interests' && !roadmapOff(kRoadmapJourneyKey) && !roadmapOff(kRoadmapRecsKey) && !roadmapOrgAccount(role);

class HomeJourneyCard extends StatelessWidget {
  const HomeJourneyCard({super.key, required this.journey, this.onTap, this.onContinue});

  final Journey journey;

  /// The card → the whole path.
  final VoidCallback? onTap;

  /// The button → the next course itself.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final j = journey;
    return AppCard(
      onTap: onTap,
      padding: AppSpace.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: onTap != null,
            label: '${j.title}. ${j.doneLine}',
            excludeSemantics: true,
            child: Row(
              children: [
                const _JourneyMark(icon: Icons.route_rounded),
                AppSpace.gapSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('مسارك التعليمي', 'Your learning path'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                      Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  AppSpace.gapXs,
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
                ],
              ],
            ),
          ),
          AppSpace.gapMd,
          _NextStep(course: j.next, label: j.next.kind == 'continue' ? t('أكمل', 'Continue') : t('خطوتك التالية', 'Your next step')),
          AppSpace.gapMd,
          JourneyTrack(journey: j),
          AppSpace.gapSm,
          Row(
            children: [
              Expanded(
                child: Text(j.doneLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ),
              if (onContinue != null) ...[
                AppSpace.gapXs,
                Flexible(
                  child: AppButton.tonal(
                    key: const ValueKey('home_journey.continue'),
                    label: journeyActionLabel(j),
                    trailingIcon: Icons.arrow_forward_rounded,
                    size: AppButtonSize.sm,
                    onPressed: onContinue,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The card's quiet mark: a vector glyph in the primary's ink on its faint tint.
class _JourneyMark extends StatelessWidget {
  const _JourneyMark({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Icon(icon, size: AppIconSize.md, color: appInk(context, c.primary)),
    );
  }
}

/// The next course on the input well: thumbnail · "Your next step" · name · where the student is in it.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.course, required this.label});

  final RmCourse course;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final co = course;
    final meta = [journeyStepState(co), if ((co.teacherName ?? '').isNotEmpty) co.teacherName!].join(' · ');
    const thumb = AppTouch.min;
    return Semantics(
      label: '$label: ${co.name}. $meta',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: SizedBox(
                width: thumb,
                height: thumb,
                child: co.imageUrl == null
                    ? ColoredBox(color: c.cardBg, child: Icon(Icons.play_lesson_rounded, size: AppIconSize.md, color: appInk(context, c.primary)))
                    : AppNetworkImage(url: co.imageUrl!, width: thumb, height: thumb, fit: BoxFit.cover, borderRadius: BorderRadius.zero),
              ),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  Text(co.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No journey yet: "Plan your learning path" · one "Pick your interests" button (D-309).
class HomeJourneyInvite extends StatelessWidget {
  const HomeJourneyInvite({super.key, required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpace.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _JourneyMark(icon: Icons.explore_rounded),
          AppSpace.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('خطّط لمسارك التعليمي', 'Plan your learning path'), style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  t('اختر ما يهمّك وسنرسم لك طريقاً واضحاً: خطوتك التالية والكورسات التي تليها.',
                      'Pick what interests you and we’ll lay out a clear way: your next step and the courses after it.'),
                  style: AppType.body(context),
                ),
                AppSpace.gapSm,
                AppButton.tonal(
                  key: const ValueKey('home_journey.pick'),
                  label: t('اختر اهتماماتك', 'Pick your interests'),
                  icon: Icons.favorite_border_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onPick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
