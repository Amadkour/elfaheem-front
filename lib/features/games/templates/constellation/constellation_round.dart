// lib/features/games/templates/constellation/constellation_round.dart — the pure rules of one Constellation set (T62).
//
//   sequence  (`order` / `complete` / `next_word`): one star per choice (the `show` order), plus a pre-lit star for every
//             slot the learner is not asked to fill; link the stars in the order of the slots. Slot k takes a star whose
//             token `eq`-matches slot k (equal words are interchangeable); a distractor star is always wrong.
//   pair      one star per `a` and per `b` (the `show_a` / `show_b` orders); link an `a` star to its `b` star, in any order.
//
// No Flutter widgets here: the Flame scene and the view call it, the tests drive it directly.
library;

import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show stageText;
import 'package:flutter_education_app/features/games/core/game_items.dart';

enum StarSide { single, a, b }

class ConstellationStar {
  const ConstellationStar({required this.label, required this.ref, this.side = StarSide.single, this.givenSlot = -1});

  final String label;

  /// Sequence: the token index (n.. = a distractor). Pair: the pair index.
  final int ref;
  final StarSide side;

  /// A star that is already in the chain (a slot the learner does not fill): its slot, else -1.
  final int givenSlot;

  bool get given => givenSlot >= 0;
}

/// The result of one try.
class StarTry {
  const StarTry({required this.right, required this.unit, required this.a, required this.first});
  final bool right;

  /// The trace unit: the slot (sequence) or the `a` index (pair).
  final int unit;

  /// The trace's `a`: `[slot, token]` or `[a index, b index]`.
  final List<int> a;

  /// First try of this unit: the one that is reported.
  final bool first;
}

class ConstellationRound {
  ConstellationRound._(this.item, this.isPair, this.stars, this.quran, this._blanks, this._n, this._eq, this.pairCount)
      : _chain = List<int>.filled(isPair ? 0 : _n, -1) {
    for (var k = 0; k < stars.length; k++) {
      final g = stars[k].givenSlot;
      if (g >= 0) _chain[g] = k;
    }
  }

  final GameItem item;
  final bool isPair;
  final List<ConstellationStar> stars;

  /// The item is Quran / Hadith: its words are drawn in the Quran role.
  final bool quran;
  final List<int> _blanks;
  final int _n, pairCount;
  final List _eq;

  /// Sequence: slot -> star index (-1 = open). Pair: unused.
  final List<int> _chain;
  final List<(int, int)> _links = [];
  final Set<int> _tried = {};

  static bool handles(GameItem i) => i.type == ItemType.sequence || i.type == ItemType.pair;

  static bool isSacred(GameItem i) => i.sacred || i.sourceKind == 'quran' || i.sourceKind == 'hadith';

  factory ConstellationRound.of(GameItem item) {
    final quran = isSacred(item);
    if (item.type == ItemType.pair) {
      final pairs = (item.body['pairs'] as List? ?? const []).cast<Map>();
      final n = pairs.length;
      List<int> perm(String k) {
        final v = item.body[k];
        final l = [for (final x in (v as List? ?? const [])) (x as num).toInt()];
        return l.length == n && l.toSet().length == n && l.every((i) => i >= 0 && i < n) ? l : [for (var i = 0; i < n; i++) i];
      }

      final stars = <ConstellationStar>[
        for (final i in perm('show_a')) ConstellationStar(label: stageText(pairs[i]['a']), ref: i, side: StarSide.a),
        for (final i in perm('show_b')) ConstellationStar(label: stageText(pairs[i]['b']), ref: i, side: StarSide.b),
      ];
      return ConstellationRound._(item, true, stars, quran, const [], n, const [], n);
    }
    final tokens = (item.body['tokens'] as List? ?? const []);
    final extra = (item.body['extra'] as List? ?? const []);
    final n = tokens.length;
    final blanks = item.intList('blanks')..sort();
    final eq = (item.body['eq'] as List?) ?? [for (var i = 0; i < n + extra.length; i++) i];
    String text(int k) => k < n ? '${tokens[k]}' : '${extra[k - n]}';
    final stars = <ConstellationStar>[
      for (var k = 0; k < n; k++)
        if (!blanks.contains(k)) ConstellationStar(label: text(k), ref: k, givenSlot: k),
      for (final k in item.show.where((i) => i >= 0 && i < n + extra.length)) ConstellationStar(label: text(k), ref: k),
    ];
    return ConstellationRound._(item, false, stars, quran, blanks, n, eq, 0);
  }

  /// The slot the next link fills (sequence); -1 when the set is done.
  int get nextSlot {
    for (final s in _blanks) {
      if (_chain[s] < 0) return s;
    }
    return -1;
  }

  int get total => isPair ? pairCount : _blanks.length;
  int get linkedCount => isPair ? _links.length : _blanks.where((s) => _chain[s] >= 0).length;
  bool get complete => total > 0 && linkedCount >= total;

  /// Every thread drawn so far, as star index pairs (pre-lit neighbours included).
  List<(int, int)> get threads {
    if (isPair) return List.unmodifiable(_links);
    return [
      for (var k = 1; k < _n; k++)
        if (_chain[k - 1] >= 0 && _chain[k] >= 0) (_chain[k - 1], _chain[k]),
    ];
  }

  /// A star that is part of the picture: linked, or given.
  bool isLinked(int star) {
    if (isPair) return _links.any((l) => l.$1 == star || l.$2 == star);
    return stars[star].given || _chain.contains(star);
  }

  /// The star the next thread starts from (sequence): the star of slot `next - 1`, else -1.
  int get tail {
    if (isPair) return -1;
    final s = nextSlot;
    return s <= 0 ? -1 : _chain[s - 1];
  }

  /// The star that is right for the next try (a hint): the first unlinked star that matches the next slot, or the first
  /// open `a` star of a pair set.
  int hintStar() {
    if (isPair) {
      for (var k = 0; k < stars.length; k++) {
        if (stars[k].side == StarSide.a && !isLinked(k)) return k;
      }
      return -1;
    }
    final s = nextSlot;
    if (s < 0) return -1;
    for (var k = 0; k < stars.length; k++) {
      if (!stars[k].given && !isLinked(k) && stars[k].ref < _n && _eq[stars[k].ref] == _eq[s]) return k;
    }
    return -1;
  }

  /// Pair: the star that belongs with [star].
  int partnerOf(int star) {
    if (!isPair) return -1;
    final s = stars[star];
    return stars.indexWhere((o) => o.side != s.side && o.ref == s.ref);
  }

  /// A try in a sequence: the learner reached [star]. Null when the set is done or the star is already in the chain.
  StarTry? trySequence(int star) {
    if (isPair || star < 0 || star >= stars.length) return null;
    final slot = nextSlot;
    if (slot < 0 || isLinked(star)) return null;
    final tok = stars[star].ref;
    final right = tok < _n && _eq[tok] == _eq[slot];
    final first = _tried.add(slot);
    if (right) _chain[slot] = star;
    return StarTry(right: right, unit: slot, a: [slot, tok], first: first);
  }

  /// A try in a pair set: [x] and [y] are the two stars the learner joined (either order). Null when they are the
  /// same side, or one is already linked.
  StarTry? tryPair(int x, int y) {
    if (!isPair || x < 0 || y < 0 || x >= stars.length || y >= stars.length) return null;
    final sx = stars[x], sy = stars[y];
    if (sx.side == sy.side || isLinked(x) || isLinked(y)) return null;
    final a = sx.side == StarSide.a ? sx : sy, b = sx.side == StarSide.a ? sy : sx;
    final right = a.ref == b.ref;
    final first = _tried.add(a.ref);
    if (right) _links.add((x, y));
    return StarTry(right: right, unit: a.ref, a: [a.ref, b.ref], first: first);
  }
}
