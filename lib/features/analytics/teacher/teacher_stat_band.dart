// The figures under an AppHeader. D-1081: the page's `HeroStat`s (exam_ui.dart) are drawn as soft-wash count cards
// (AppStatCard in an AppKpiGrid, the tones taking turns); anything else keeps the compact mesh card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppBlockTone, AppGradientSurface, AppKpiGrid, AppStatCard;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/exams/legacy/student/exam_ui.dart' show HeroStat;

const _kTones = [AppBlockTone.emerald, AppBlockTone.gold, AppBlockTone.sky, AppBlockTone.peach];

class TeacherStatBand extends StatelessWidget {
  const TeacherStatBand({super.key, required this.stats, this.color, this.seed = 0});

  /// `HeroStat`s: each one expands to its share of the line.
  final List<Widget> stats;

  /// The main colour (the brand primary by default).
  final Color? color;
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (stats.isNotEmpty && stats.every((w) => w is HeroStat)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
        child: AppKpiGrid(children: [
          for (final (i, w) in stats.cast<HeroStat>().indexed)
            AppStatCard(icon: w.icon, value: w.value, label: w.label, tone: _kTones[(i + seed) % _kTones.length]),
        ]),
      );
    }
    return _band();
  }

  Widget _band() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
        child: AppGradientSurface(
          color: color,
          seed: seed,
          radius: AppRadius.card,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.xs),
              stats[i],
            ],
          ]),
        ),
      );
}
