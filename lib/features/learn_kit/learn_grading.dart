// lib/features/learn_kit/learn_grading.dart — the pure parts of the learn kit (D-1346): marks, stars, shuffling.
library;

import 'dart:math';

import 'package:flutter_education_app/config/app_config.dart';

/// How one option (or one placed item) is drawn.
enum LearnMark {
  /// Not chosen, nothing revealed.
  idle,

  /// Chosen, not checked yet.
  selected,

  /// Checked and right.
  correct,

  /// Checked and wrong.
  wrong,

  /// The right answer the person did not pick (shown after a wrong pick).
  missed,
}

/// 0–3 stars for [score] of [max]: the server's rule (`games_service.stars_for`), so the end screen can show the
/// stars before the server answers. The server's own number wins once it is there.
int learnStars(num score, num max) {
  if (max <= 0) return 0;
  final p = score / max;
  return p >= 0.9 ? 3 : p >= 0.6 ? 2 : p >= 0.3 ? 1 : 0;
}

/// [score] of [max] as a whole percentage (0 when [max] is 0).
int learnPercent(num score, num max) => max <= 0 ? 0 : ((score / max) * 100).round().clamp(0, 100);

/// A shuffled copy of [items]. With [avoidIdentity] (the default) a list of two or more distinct items never comes
/// back in its original order, so an "order" or "match" round is never solved before it starts.
List<T> learnShuffle<T>(List<T> items, {Random? random, bool avoidIdentity = true}) {
  final r = random ?? Random();
  final out = [...items];
  if (out.length < 2) return out;
  for (var attempt = 0; attempt < 8; attempt++) {
    out.shuffle(r);
    if (!avoidIdentity || !_sameOrder(out, items)) return out;
  }
  // every try came back in order (e.g. all items equal): rotate by one, which differs whenever the items do
  return [...items.skip(1), items.first];
}

bool _sameOrder<T>(List<T> a, List<T> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [ar] or [en] by the app's language; the other one when that one is empty.
String learnText(String? ar, String? en) {
  final a = (ar ?? '').trim(), e = (en ?? '').trim();
  if (AppConfig.lang == 'ar') return a.isNotEmpty ? a : e;
  return e.isNotEmpty ? e : a;
}
