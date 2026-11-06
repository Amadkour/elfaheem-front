// lib/design/master_detail/entity_learner.dart — a learner's own place in a course (D-290, phase 7): the one block at
// the top of the course panel for a student (or their parent). Simple and motivating:
//
//   ┌──────────────────────────────────┐
//   │  (ring 64 %)   In progress       │   the ring on the state's colour, then one sentence that fits the
//   │                Keep going, you … │   progress; the dates under it
//   │                Enrolled … · …    │
//   └──────────────────────────────────┘
//
// A withdrawn enrollment draws its date and reason in a tinted box instead of the ring's sentence. Plain values only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';

import '../app_kit.dart';
import 'entity_specs.dart';

/// The sentence of [mine]: a word about where the learner stands.
String entityLearnerLine(EntityEnrollment mine, {bool self = true}) {
  final prefix = self ? 'md_p7_mine_' : 'md_p7_child_';
  final p = mine.progress ?? 0;
  final step = switch (mine.state) {
    'completed' => 'completed',
    'withdrawn' => 'withdrawn',
    'expired' => 'expired',
    'pending' => 'pending',
    _ => p <= 0 ? 'start' : (p < 30 ? 'early' : (p < 75 ? 'middle' : 'close')),
  };
  return '$prefix$step'.tr;
}

class EntityLearnerCard extends StatelessWidget {
  const EntityLearnerCard({super.key, required this.mine, this.self = true});

  final EntityEnrollment mine;

  /// The learner reads it (else a parent, about their child).
  final bool self;

  static const double ringSize = 76;

  @override
  Widget build(BuildContext context) {
    final state = mine.state;
    final tone = appToneColor(context, mdStateTone(state));
    final value = (mine.progress ?? 0).clamp(0, 100).toDouble();
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Semantics(
            label: '${'md_progress'.tr} ${mdPercent(value)}',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: ringSize,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                  child: CircularProgressIndicator(
                    value: value / 100,
                    strokeWidth: AppSpace.xs,
                    strokeCap: StrokeCap.round,
                    color: tone,
                    backgroundColor: context.colors.divider,
                  ),
                ),
                Text(mdPercent(value), style: AppType.figure(context).copyWith(fontSize: 17)),
              ]),
            ),
          ),
          AppSpace.gapMd,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              AppStatusBadge(label: mdStateLabel(state), tone: mdStateTone(state), dense: true),
              const SizedBox(height: AppSpace.xs),
              Text(entityLearnerLine(mine, self: self), maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        for (final w in enrollmentMeta(context, mine)) ...[w, const SizedBox(height: AppSpace.xxs)],
      ]),
    );
  }
}
