// lib/features/learn_kit/learn_progress.dart — the progress parts of the learn kit (D-1346): "Question 3 of 8" with a
// filled bar, and the three stars.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// "Question 3 of 8" (or [label]) and a bar filled to [current] / [total]; [score] adds "Score 2" at the end.
class LearnProgressHeader extends StatelessWidget {
  const LearnProgressHeader({super.key, required this.current, required this.total, this.label, this.score});

  /// 1-based: the step on screen.
  final int current;
  final int total;

  /// Replaces "Question 3 of 8".
  final String? label;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final text = label ?? (ar ? 'السؤال $current من $total' : 'Question $current of $total');
    final v = total <= 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    // one leaf with the step AND the score (a label on a node with children is dropped by the browser on the web)
    return Semantics(
      container: true,
      label: score == null ? text : '$text, ${ar ? 'النقاط $score' : 'Score $score'}',
      value: '${(v * 100).round()}%',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(text, style: AppType.label(context).copyWith(color: c.textMedium))),
          if (score != null)
            Text(ar ? 'النقاط $score' : 'Score $score',
                style: AppType.label(context).copyWith(color: c.primary, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: AppSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: AppSpace.xs,
            child: AppFill(
              value: v,
              builder: (context, f) => Stack(fit: StackFit.expand, children: [
                ColoredBox(color: c.inputBg),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: f.clamp(0.0, 1.0),
                  child: ColoredBox(color: c.primary),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Three stars, the first [stars] filled in gold (the achievement tone); read as "2 of 3 stars".
class LearnStars extends StatelessWidget {
  const LearnStars({super.key, required this.stars, this.size = AppIconSize.md, this.of = 3});

  final int stars;
  final int of;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = stars.clamp(0, of);
    final ar = AppConfig.lang == 'ar';
    return Semantics(
      label: ar ? '$n من $of نجوم' : '$n of $of stars',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < of; i++)
          Icon(i < n ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size, color: i < n ? appToneColor(context, AppTone.gold) : c.textLight),
      ]),
    );
  }
}
