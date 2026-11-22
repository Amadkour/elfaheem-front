// lib/features/games/champions/champions_strip.dart — the champions strip on top of the Games tab (Games v3 §2.4):
// today's top 3 of my board and my own place, from the `champions` block of GET /games (no request of its own);
// tapping it opens the Hall of Champions. Kill switch `games.champions` (the tab does not draw it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/champions/champions_page.dart' show championTone, championsCountdownText;

class ChampionsStrip extends StatelessWidget {
  const ChampionsStrip({super.key, required this.data, this.onOpen, this.now});

  final ChampionsStripData data;
  final VoidCallback? onOpen;

  /// The clock for the countdown (tests pass a fixed one).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = data.me;
    final end = data.periodEnd;
    final nowUtc = now ?? DateTime.now().toUtc();
    final line = [
      if (me?.rank != null) t('ترتيبك ${me!.rank}', 'You are number ${me.rank}'),
      if (end != null) championsCountdownText(end.difference(nowUtc)),
    ].join(' · ');
    return Semantics(
      button: true,
      label: [t('أبطال اليوم', 'Today\'s champions'), for (final r in data.top) '${r.rank ?? ''} ${r.name}', line].join(', '),
      excludeSemantics: true,
      child: AppCard(
        key: const ValueKey('games.champions.strip'),
        onTap: onOpen,
        child: Row(children: [
          Icon(Icons.emoji_events_rounded, color: appToneColor(context, AppTone.gold)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('أبطال اليوم', 'Today\'s champions')} · ${data.scope.name}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              const SizedBox(height: AppSpace.xxs),
              if (data.top.isEmpty)
                Text(t('لا بطل بعد: العب 3 ألعاب مختلفة لتدخل اللوحة', 'No champion yet: play 3 different games to enter'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context))
              else
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  for (final r in data.top) _Chip(row: r),
                ]),
              if (line.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.row});

  final ChampionRow row;

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockColors.of(context, championTone(row.rank));
    final name = row.isMe ? t('أنت', 'You') : (row.name.isEmpty ? t('طالب', 'Student') : row.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: tone.surface, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text('${row.rank ?? ''}. $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone.ink)),
    );
  }
}
