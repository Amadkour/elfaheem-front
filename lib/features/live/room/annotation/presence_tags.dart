// lib/features/live/room/annotation/presence_tags.dart
//
// What the presence of D-093 looks like (Zoom / Miro / FigJam style), on a shared screen's annotation and on the
// whiteboard:
//
//   PresenceTagsPainter  for every tag of live_presence.dart: a small nib ring on the pen tip and, beside it, a pill in
//                        the person's ink colour with their name (white or dark label, whichever reads). The pill sits
//                        below and after the tip, and flips to the other side near an edge so it never leaves the
//                        content. Names are drawn with the platform's bidi: an Arabic name runs right to left by itself.
//   AuthorLabelChip      the "Drawn by …" chip of an item under the mouse / a long press, when the host turned
//                        "Show who drew what" on.
//
// Interface ink, not content: the tags are not in the board's PNG or its recording frames.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/annotation/live_presence.dart';

/// Whether [text] reads right to left (its first strong letter; an empty name follows [fallbackRtl]).
bool presenceIsRtl(String text, {bool fallbackRtl = false}) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFC)) return true;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F) || (r >= 0x370 && r <= 0x58F)) {
      return false;
    }
  }
  return fallbackRtl;
}

/// Where a tag's pill goes for a tip at [tip] inside [bounds]: below and after the tip, flipped near an edge.
/// Pure (test/org/live_presence_test.dart).
Rect presenceTagRect(Offset tip, Size pill, Rect bounds, {double gap = 9}) {
  var left = tip.dx + gap;
  var top = tip.dy + gap + 2;
  if (left + pill.width > bounds.right - 2) left = tip.dx - gap - pill.width;
  if (top + pill.height > bounds.bottom - 2) top = tip.dy - gap - pill.height;
  left = left.clamp(bounds.left + 2, math.max(bounds.left + 2, bounds.right - pill.width - 2)).toDouble();
  top = top.clamp(bounds.top + 2, math.max(bounds.top + 2, bounds.bottom - pill.height - 2)).toDouble();
  return Rect.fromLTWH(left, top, pill.width, pill.height);
}

class PresenceTagsPainter extends CustomPainter {
  PresenceTagsPainter({
    required this.presence,
    required this.marks,
    required this.toLocal,
    required this.bounds,
    this.fallbackRtl = false,
    this.visible,
  }) : super(repaint: presence);

  final LivePresence presence;

  /// The marks to draw (already filtered: page, who is shown).
  final Iterable<PresenceMark> Function() marks;

  /// A mark's normalised position → this painter's local coordinates.
  final Offset Function(double x, double y) toLocal;

  /// Where tags may go (the content's visible rect, local coordinates).
  final Rect Function(Size size) bounds;
  final bool fallbackRtl;

  /// Whether a mark is drawn at all (who is shown; null: all).
  final bool Function(PresenceMark m)? visible;

  static final LinkedHashMap<String, TextPainter> _labels = LinkedHashMap();

  static TextPainter _label(String name, int ink, bool rtl, {bool compact = false}) {
    final family = AppFonts.family;
    final key = '$family|$ink|$rtl|$compact|$name';
    final hit = _labels.remove(key);
    if (hit != null) {
      _labels[key] = hit; // most recent last
      return hit;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(fontFamily: family, fontSize: compact ? 10.5 : 12, height: 1.15, fontWeight: FontWeight.w700, color: Color(ink), letterSpacing: 0.1),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: compact ? 120 : 168);
    _labels[key] = tp;
    while (_labels.length > 64) {
      _labels.remove(_labels.keys.first)?.dispose();
    }
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = bounds(size);
    if (area.isEmpty) return;
    for (final m in marks()) {
      if (visible != null && !visible!(m)) continue;
      final a = presence.opacity(m);
      if (a <= 0) continue;
      final tip = toLocal(m.shownX, m.shownY);
      if (!area.inflate(24).contains(tip)) continue;
      paintTag(canvas, tip: tip, name: m.name, color: m.color, opacity: a, bounds: area, fallbackRtl: fallbackRtl);
    }
  }

  /// One tag (also used by the visual renders).
  static void paintTag(Canvas canvas,
      {required Offset tip, required String name, required int color, double opacity = 1, required Rect bounds, bool fallbackRtl = false}) {
    if (name.isEmpty) return;
    final fill = Color(presenceTagColor(color));
    final ink = presenceInkOn(fill.toARGB32());
    final rtl = presenceIsRtl(name, fallbackRtl: fallbackRtl);
    // A small content (a phone's view of a shared screen): a smaller tag, so three drawers do not cover it.
    final compact = bounds.width < 480;
    final tp = _label(name, ink, rtl, compact: compact);
    final padH = compact ? 6.0 : 8.0, padV = compact ? 3.0 : 4.0;
    final pill = Size(tp.width + padH * 2, math.max(compact ? 18.0 : 22.0, tp.height + padV * 2));
    final r = presenceTagRect(tip, pill, bounds);
    // The corner nearest the tip is the sharp one: the pill "points" at the pen.
    final nearLeft = r.left >= tip.dx, nearTop = r.top >= tip.dy;
    final round = Radius.circular(pill.height / 2), sharp = const Radius.circular(3);
    final rr = RRect.fromRectAndCorners(
      r,
      topLeft: nearLeft && nearTop ? sharp : round,
      topRight: !nearLeft && nearTop ? sharp : round,
      bottomLeft: nearLeft && !nearTop ? sharp : round,
      bottomRight: !nearLeft && !nearTop ? sharp : round,
    );
    final layerPaint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.saveLayer(r.inflate(14).expandToInclude(Rect.fromCircle(center: tip, radius: 8)), layerPaint);
    // shadow
    canvas.drawRRect(
      rr.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x52000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    // a hairline that keeps a light tag apart from a light page
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink == 0xFF111827 ? const Color(0x33000000) : const Color(0x40FFFFFF),
    );
    tp.paint(canvas, Offset(r.left + padH, r.top + (r.height - tp.height) / 2));
    // the nib ring on the tip
    canvas.drawCircle(tip, compact ? 4.4 : 5.2, Paint()..color = const Color(0xF2FFFFFF));
    canvas.drawCircle(tip, compact ? 3.0 : 3.6, Paint()..color = fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PresenceTagsPainter old) => !identical(old.presence, presence) || old.fallbackRtl != fallbackRtl;
}

/// "Drawn by Mona" (or "Drawn by you") beside the pointer.
class AuthorLabelChip extends StatelessWidget {
  const AuthorLabelChip({super.key, required this.name, this.mine = false, this.color});

  final String name;
  final bool mine;

  /// The item's ink (the dot before the name).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    final label = mine ? t('رسمته أنت', 'Drawn by you') : t('رسمه $name', 'Drawn by $name');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('presence.author_label'),
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 10, 5),
          decoration: BoxDecoration(
            color: LivePalette.surfaceHi.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LivePalette.glassBorder),
            boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color == null ? LivePalette.accent : Color(presenceTagColor(color!.toARGB32())),
                shape: BoxShape.circle,
                border: Border.all(color: LivePalette.textHigh.withValues(alpha: 0.7), width: 1),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w700, c: LivePalette.textHigh)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The chip's place for a pointer at [at] inside [area] (above and after the pointer, kept inside).
Offset authorLabelOffset(Offset at, Rect area, {double width = 200, double height = 30}) {
  var x = at.dx + 12;
  var y = at.dy - height - 10;
  if (x + width > area.right) x = at.dx - width - 12;
  if (y < area.top) y = at.dy + 18;
  return Offset(x.clamp(area.left, math.max(area.left, area.right - width)).toDouble(),
      y.clamp(area.top, math.max(area.top, area.bottom - height)).toDouble());
}
