// The figures under an AppHeader: a compact mesh card with the page's `HeroStat`s (exam_ui.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppGradientSurface;
import 'package:flutter_education_app/design/app_tokens.dart';

class TeacherStatBand extends StatelessWidget {
  const TeacherStatBand({super.key, required this.stats, this.color, this.seed = 0});

  /// `HeroStat`s: each one expands to its share of the line.
  final List<Widget> stats;

  /// The main colour (the brand primary by default).
  final Color? color;
  final int seed;

  @override
  Widget build(BuildContext context) => Padding(
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
