// lib/features/games/learner/result_sheet.dart — what a Games v4 play adds under the finish view (T48): the coins the
// play earned and the levels it unlocked. Plain values, no provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/plural.dart';

class GameResultExtras extends StatelessWidget {
  const GameResultExtras({super.key, required this.coinsAwarded, this.coins, this.unlocked = 0});

  final int coinsAwarded;

  /// The learner's coins after the play (null = unknown).
  final int? coins;

  /// How many levels this play unlocked.
  final int unlocked;

  @override
  Widget build(BuildContext context) {
    if (coinsAwarded <= 0 && unlocked <= 0) return const SizedBox.shrink();
    final c = context.colors;
    final lines = <(IconData, String)>[
      if (coinsAwarded > 0)
        (
          Icons.monetization_on_rounded,
          coins == null
              ? t('+$coinsAwarded عملة', '+$coinsAwarded coins')
              : t('+$coinsAwarded عملة · رصيدك $coins', '+$coinsAwarded coins · you have $coins'),
        ),
      if (unlocked > 0)
        (
          Icons.lock_open_rounded,
          countText(unlocked,
              ar1: 'فتحتَ مستوىً جديداً',
              ar2: 'فتحتَ مستويين جديدين',
              arFew: 'فتحتَ $unlocked مستويات جديدة',
              arMany: 'فتحتَ $unlocked مستوىً جديداً',
              en1: 'You unlocked a new level',
              en: 'You unlocked $unlocked new levels'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: AppCard(
        key: const ValueKey('games.v4.extras'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs / 2),
              child: Row(children: [
                Icon(l.$1, size: AppIconSize.sm, color: c.primary),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(l.$2, style: appText(14, w: FontWeight.w600))),
              ]),
            ),
        ]),
      ),
    );
  }
}
