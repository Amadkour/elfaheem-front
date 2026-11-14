// lib/features/live/room/annotation/live_presence.dart
//
// Who is drawing right now (D-093): the name tags that follow another person's pen tip (or the shape / text box they
// are moving) on the screen-share annotation and on the whiteboard, Zoom / Miro style. Pure logic, no widget:
//
//   • fed by the packets the room already receives (ink points, a shape or a text box being put, the laser), keyed by
//     the REAL LiveKit sender identity — no extra message, nothing in a payload names anybody;
//   • a tag stays fully visible while the person's stroke is open and for [LivePresence.hold] (1.5 s) after their last
//     activity, then fades out over [LivePresence.fade];
//   • the drawn position glides toward the last reported one ([LivePresence.step]: an exponential follow with a 45 ms
//     time constant), so a tag does not jump from batch to batch (points arrive every ~33 ms);
//   • the label is the participant's display name made safe ([presenceSafeName]: bidi controls and control
//     characters removed, whitespace collapsed, at most 24 characters + "…"); a guest has only the display name they
//     typed, never an identity.
//
// The local person's own activity is never tracked: a drawer sees the tags of the others, not their own.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One person's tag.
class PresenceMark {
  PresenceMark({
    required this.identity,
    required this.name,
    required this.color,
    required this.x,
    required this.y,
    required this.page,
    required this.at,
    this.active = false,
  })  : shownX = x,
        shownY = y;

  final String identity;
  String name;

  /// ARGB: the ink they draw with (or their stable colour).
  int color;

  /// The last reported position (normalised to the content: the shared frame or the board page).
  double x, y;

  /// Where the tag is drawn now (glides toward [x], [y]).
  double shownX, shownY;

  /// The board page ('' on a shared screen).
  String page;

  /// The last activity.
  DateTime at;

  /// A stroke of theirs is still open (the pen is down): the tag never fades meanwhile.
  bool active;
}

class LivePresence extends ChangeNotifier {
  LivePresence({
    DateTime Function()? now,
    this.hold = const Duration(milliseconds: 1500),
    this.fade = const Duration(milliseconds: 350),
    this.follow = const Duration(milliseconds: 45),
    this.maxMarks = 24,
  }) : now = now ?? DateTime.now;

  final DateTime Function() now;

  /// Fully visible this long after the last activity.
  final Duration hold;

  /// Then fades out over this.
  final Duration fade;

  /// The time constant of the glide toward the reported position.
  final Duration follow;

  /// More simultaneous drawers than this: the oldest tag goes.
  final int maxMarks;

  final Map<String, PresenceMark> _marks = {};
  DateTime? _lastStep;

  Iterable<PresenceMark> get marks => _marks.values;
  bool get isEmpty => _marks.isEmpty;
  PresenceMark? markOf(String identity) => _marks[identity];

  /// The marks on [page] ('' = a shared screen).
  Iterable<PresenceMark> on(String page) => _marks.values.where((m) => m.page == page);

  /// [identity] did something at ([x], [y]) on [page]. [active]: their stroke is open (null: unchanged).
  /// [color]: their ink (null: keep the last one, else their stable colour).
  void mark(String identity, {required String name, required double x, required double y, String page = '', int? color, bool? active}) {
    if (identity.isEmpty || !x.isFinite || !y.isFinite) return;
    final t = now();
    final m = _marks[identity];
    if (m == null) {
      if (_marks.length >= maxMarks) {
        final oldest = _marks.values.reduce((a, b) => a.at.isBefore(b.at) ? a : b);
        _marks.remove(oldest.identity);
      }
      _marks[identity] = PresenceMark(
        identity: identity,
        name: name,
        color: color ?? presenceColorFor(identity),
        x: x,
        y: y,
        page: page,
        at: t,
        active: active ?? false,
      );
    } else {
      if (m.page != page) {
        // A new page: no glide across pages.
        m.shownX = x;
        m.shownY = y;
      }
      m
        ..name = name
        ..x = x
        ..y = y
        ..page = page
        ..at = t;
      if (color != null) m.color = color;
      if (active != null) m.active = active;
    }
    notifyListeners();
  }

  /// Their stroke ended (the tag starts its [hold] now).
  void end(String identity) {
    final m = _marks[identity];
    if (m == null) return;
    m
      ..active = false
      ..at = now();
    notifyListeners();
  }

  void remove(String identity) {
    if (_marks.remove(identity) != null) notifyListeners();
  }

  void clear() {
    if (_marks.isEmpty) return;
    _marks.clear();
    notifyListeners();
  }

  /// An open stroke with no new point for this long counts as finished (its drawer left mid-stroke, or holds the pen
  /// still): the tag fades like any other.
  static const staleActive = Duration(seconds: 5);

  /// 1 while active or within [hold] of the last activity, then down to 0 over [fade].
  double opacity(PresenceMark m) {
    final age = now().difference(m.at);
    if (m.active && age < staleActive) return 1;
    if (m.active) {
      final f = fade.inMicroseconds;
      return f <= 0 ? 0 : (1 - (age - staleActive).inMicroseconds / f).clamp(0.0, 1.0).toDouble();
    }
    if (age <= hold) return 1;
    final f = fade.inMicroseconds;
    if (f <= 0) return 0;
    return (1 - (age - hold).inMicroseconds / f).clamp(0.0, 1.0).toDouble();
  }

  /// One animation frame: glides the shown positions toward the reported ones and drops faded marks. Returns
  /// whether anything is still visible or moving (the caller's ticker keeps running while true).
  bool step() {
    final t = now();
    final last = _lastStep;
    _lastStep = t;
    final dt = last == null ? 0.016 : math.max(0.0, t.difference(last).inMicroseconds / 1e6);
    final k = follow.inMicroseconds <= 0 ? 1.0 : 1 - math.exp(-dt / (follow.inMicroseconds / 1e6));
    var changed = false;
    final gone = <String>[];
    for (final m in _marks.values) {
      if (opacity(m) <= 0) {
        gone.add(m.identity);
        continue;
      }
      final dx = m.x - m.shownX, dy = m.y - m.shownY;
      if (dx.abs() > 1e-5 || dy.abs() > 1e-5) {
        m.shownX += dx * k;
        m.shownY += dy * k;
        if ((m.x - m.shownX).abs() < 1e-5) m.shownX = m.x;
        if ((m.y - m.shownY).abs() < 1e-5) m.shownY = m.y;
      }
      changed = true; // visible: the opacity may be changing too
    }
    for (final id in gone) {
      _marks.remove(id);
    }
    if (changed || gone.isNotEmpty) notifyListeners();
    if (_marks.isEmpty) _lastStep = null;
    return _marks.isNotEmpty;
  }
}

/// A name that is safe to draw inside the content: bidi embeddings / overrides / isolates and control characters
/// removed (a name cannot flip the text around it), whitespace collapsed, at most [max] characters (+ "…"). Null or
/// empty after cleaning → [fallback].
String presenceSafeName(String? raw, {int max = 24, String fallback = ''}) {
  if (raw == null) return fallback;
  final out = StringBuffer();
  var space = false;
  for (final r in raw.runes) {
    if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0xA0 || r == 0x3000) {
      space = out.isNotEmpty;
      continue;
    }
    if (_isInvisible(r)) continue;
    if (space) {
      out.write(' ');
      space = false;
    }
    out.writeCharCode(r);
  }
  final s = out.toString();
  if (s.isEmpty) return fallback;
  final runes = s.runes.toList();
  if (runes.length <= max) return s;
  return '${String.fromCharCodes(runes.take(max)).trimRight()}…';
}

bool _isInvisible(int r) =>
    r < 0x20 ||
    (r >= 0x7F && r <= 0x9F) ||
    r == 0x061C || // Arabic letter mark
    r == 0x200E ||
    r == 0x200F ||
    (r >= 0x202A && r <= 0x202E) ||
    (r >= 0x2066 && r <= 0x2069) ||
    r == 0xFEFF ||
    (r >= 0xFFF9 && r <= 0xFFFB);

/// A colour per person, the same on every device (FNV-1a of the identity over a palette that reads on light and dark
/// content).
int presenceColorFor(String identity) {
  var h = 0x811C9DC5;
  for (final c in identity.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return kPresencePalette[h % kPresencePalette.length];
}

/// Saturated, mid-light colours: a white or a dark label reads on each ([presenceInkOn]).
const kPresencePalette = <int>[
  0xFF2563EB, // blue
  0xFFDB2777, // pink
  0xFF059669, // emerald
  0xFFD97706, // amber
  0xFF7C3AED, // violet
  0xFF0891B2, // cyan
  0xFFDC2626, // red
  0xFF65A30D, // lime
];

/// The label colour on a tag of [argb]: dark on a light tag (chalk, yellow), white otherwise.
int presenceInkOn(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  double lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  // The contrast of white vs a near-black ink on this colour: the higher wins.
  final withWhite = 1.05 / (l + 0.05);
  final withDark = (l + 0.05) / (0.0144 + 0.05);
  return withWhite >= withDark ? 0xFFFFFFFF : 0xFF111827;
}

/// The tag's fill: the ink made opaque (a highlighter's colour is translucent on the page, never on its tag).
int presenceTagColor(int argb) => 0xFF000000 | (argb & 0x00FFFFFF);
