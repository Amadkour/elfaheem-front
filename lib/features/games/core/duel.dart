// lib/features/games/core/duel.dart — the plain values of a Ghost Duel (Games v4 T63, CONTRACT §8 "The duel").
//
//   DuelGhost    the opponent's recorded round: `events` are `[ms, right]` per counted answer, as the ghost route
//                gives them; `id` is the ghost play's id (sent back as `ghost_play_id`, null for the training bot)
//   botDuelGhost the built-in training partner: 70 % right at par pace, the same numbers as the server's
//   duelWins     the contract's rule: share right first (cross-multiplied), then the shorter time; a tie on both is
//                not a win. The app uses it for the picture and for an offline play; online the server's verdict
//                is what is shown.
library;

class DuelGhost {
  const DuelGhost({
    this.id,
    required this.name,
    required this.score,
    required this.maxScore,
    required this.durationMs,
    required this.events,
    this.bot = false,
  });

  /// The ghost play's id, or null for the training partner.
  final int? id;
  final String name;
  final int score, maxScore, durationMs;
  final List<(int, int)> events;
  final bool bot;

  /// What the share of the ghost's line is measured against.
  int get total => maxScore > 0 ? maxScore : (events.isEmpty ? 1 : events.length);
}

/// The training partner of a round of [items] questions whose par pace is [parMs] (`sum of the items' par`): 7 of 10
/// right (the same share for any length), one answer every `parMs / items`.
DuelGhost botDuelGhost({required int items, required int parMs, String name = ''}) {
  final n = items < 1 ? 1 : items;
  final pace = parMs > 0 ? parMs : n * 6000;
  var right = 0;
  final events = <(int, int)>[];
  for (var i = 0; i < n; i++) {
    final hit = ((i + 1) * 7) ~/ 10 > (i * 7) ~/ 10 ? 1 : 0;
    right += hit;
    events.add((((i + 1) * pace) ~/ n, hit));
  }
  return DuelGhost(name: name, score: right, maxScore: n, durationMs: pace, events: events, bot: true);
}

/// CONTRACT §8: `my_score × their_max > their_score × my_max`, or equal shares and a shorter time.
bool duelWins({
  required int myScore,
  required int myMax,
  required int myMs,
  required int theirScore,
  required int theirMax,
  required int theirMs,
}) {
  final a = myScore * theirMax, b = theirScore * myMax;
  return a > b || (a == b && myMs < theirMs);
}
