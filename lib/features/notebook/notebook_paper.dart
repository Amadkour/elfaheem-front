// lib/features/notebook/notebook_paper.dart
//
// The look of the دفتر: a ruled sheet with the margin line on the reading-start edge (SubjectProfile `pv-nb`), the
// pages drawn on it (caption, headings in the editorial face, paragraphs, bullets, highlighted lines, equations,
// the sticky note that slaps on, M4) and the ink of a page. Plain values only: tests pump these directly.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/notebook/notebook_models.dart';

/// The ruled lines' pitch: one line of the sheet.
const double kNotebookLine = AppSpace.xl;

/// How far the margin line sits from the reading-start edge.
const double kNotebookMargin = AppSpace.xl + AppSpace.xs;

/// The paper's colours, from the theme's roles: a warm tint of the card, the kit's hairline for the rules, the live
/// colour (softened) for the margin.
class NotebookPaperColors {
  const NotebookPaperColors({required this.paper, required this.edge, required this.rule, required this.margin});

  final Color paper, edge, rule, margin;

  static NotebookPaperColors of(BuildContext context) {
    final c = context.colors;
    final warm = c.kit.warmTone;
    return NotebookPaperColors(
      paper: Color.lerp(c.cardBg, warm.tint, c.isDark ? 0.18 : 0.45)!,
      edge: Color.lerp(warm.tint, warm.color, 0.25)!,
      rule: c.kit.line,
      margin: c.kit.live.color.withValues(alpha: 0.55),
    );
  }
}

/// The ruled sheet around [child]. [lines] draws the rules (off for a loading bone).
class NotebookPaper extends StatelessWidget {
  const NotebookPaper({super.key, required this.child, this.lines = true});

  final Widget child;
  final bool lines;

  @override
  Widget build(BuildContext context) {
    final p = NotebookPaperColors.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: p.edge, width: AppBorder.hairline),
        boxShadow: AppShadow.card(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: CustomPaint(
          painter: lines ? _RulesPainter(rule: p.rule, margin: p.margin, rtl: rtl) : null,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              kNotebookMargin + AppSpace.md,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RulesPainter extends CustomPainter {
  _RulesPainter({required this.rule, required this.margin, required this.rtl});

  final Color rule, margin;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Paint()
      ..color = rule
      ..strokeWidth = AppBorder.hairline;
    for (var y = kNotebookLine + AppSpace.xs; y < size.height; y += kNotebookLine) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), r);
    }
    final x = rtl ? size.width - kNotebookMargin : kNotebookMargin;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = AppBorder.strong,
    );
  }

  @override
  bool shouldRepaint(_RulesPainter old) => old.rule != rule || old.margin != margin || old.rtl != rtl;
}

/// A colour of a stroke (`#RRGGBB`) on the canvas; an unreadable value draws in [fallback].
Color notebookInkColor(String hex, Color fallback) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  final v = int.tryParse(h, radix: 16);
  if (v == null || h.length != 6) return fallback;
  return Color(v).withAlpha(255);
}

/// A theme colour as the server's `#RRGGBB`.
String notebookHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Text line height that sits a body line on the sheet's rules.
double _ruled(double fontSize) => kNotebookLine / fontSize;

/// One page on the sheet: its caption, then its blocks, then its ink. [onLongPress] opens the page's actions.
class NotebookPageView extends StatelessWidget {
  const NotebookPageView({super.key, required this.page, required this.caption, this.onTap, this.onLongPress, this.index = 0});

  final NotePage page;
  final String caption;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sticky = page.blocks.where((b) => b.kind == NoteBlockKind.sticky).toList();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: c.textLight, height: _ruled(AppType.meta(context).fontSize ?? 12)),
        ),
        for (final b in page.blocks)
          if (b.kind != NoteBlockKind.sticky && b.text.trim().isNotEmpty) NotebookBlockView(block: b),
        if (page.ink != null && !page.ink!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: NotebookInkView(ink: page.ink!),
          ),
        if (page.isEmpty && (page.preview ?? '').isNotEmpty)
          Text(page.preview!, style: AppType.body(context).copyWith(height: _ruled(AppType.body(context).fontSize ?? 14))),
        for (final s in sticky)
          if (s.text.trim().isNotEmpty) NotebookSticky(text: s.text),
      ],
    );
    if (onTap == null && onLongPress == null) return body;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: body,
      ),
    );
  }
}

/// One typed block drawn on the sheet.
class NotebookBlockView extends StatelessWidget {
  const NotebookBlockView({super.key, required this.block});

  final NoteBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = AppType.body(context).copyWith(color: c.textDark);
    final line = _ruled(body.fontSize ?? 14);
    switch (block.kind) {
      case NoteBlockKind.heading:
        final h = AppType.headline(context).copyWith(color: c.kit.hot);
        return Text(block.text, style: h.copyWith(height: kNotebookLine * 1.25 / (h.fontSize ?? 24)));
      case NoteBlockKind.bullet:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•', style: body.copyWith(height: line, color: c.kit.hot)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(block.text, style: body.copyWith(height: line))),
          ],
        );
      case NoteBlockKind.highlight:
        return Text.rich(
          TextSpan(
            text: block.text,
            style: body.copyWith(height: line, background: Paint()..color = c.kit.accent(AppAccent.sun).color.withValues(alpha: 0.55)),
          ),
        );
      case NoteBlockKind.equation:
        return Text(
          block.text,
          textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          style: AppType.bodyStrong(context).copyWith(color: c.textDark, height: line),
        );
      case NoteBlockKind.sticky:
        return NotebookSticky(text: block.text);
      case NoteBlockKind.paragraph:
        return Text(block.text, style: body.copyWith(height: line));
    }
  }
}

/// The yellow sticky note ("واجب: …"), slapped on once (M4).
class NotebookSticky extends StatelessWidget {
  const NotebookSticky({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final sun = context.colors.kit.accent(AppAccent.sun);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppSlap(
          tilt: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            decoration: BoxDecoration(
              color: Color.lerp(sun.tint, sun.color, 0.45),
              boxShadow: AppShadow.card(context),
            ),
            child: Text(text, style: AppType.label(context).copyWith(color: sun.ink, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// A page's ink, scaled to the width it is given (the canvas's own aspect kept).
class NotebookInkView extends StatelessWidget {
  const NotebookInkView({super.key, required this.ink});

  final NoteInk ink;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: ink.width / ink.height,
    child: CustomPaint(painter: NotebookInkPainter(strokes: ink.strokes, space: Size(ink.width, ink.height), fallback: context.colors.textDark)),
  );
}

/// Draws strokes held in [space] coordinates into the painter's size: smooth quadratic paths with round caps, the
/// highlighter wide and see-through.
class NotebookInkPainter extends CustomPainter {
  NotebookInkPainter({required this.strokes, required this.space, required this.fallback, this.live});

  final List<InkStroke> strokes;
  final Size space;
  final Color fallback;

  /// The stroke being drawn right now (repaints on every point).
  final InkStroke? live;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / space.width, sy = size.height / space.height;
    canvas.save();
    canvas.scale(sx, sy);
    for (final s in [...strokes, ?live]) {
      _stroke(canvas, s);
    }
    canvas.restore();
  }

  void _stroke(Canvas canvas, InkStroke s) {
    if (s.points.isEmpty) return;
    final color = notebookInkColor(s.color, fallback);
    final hl = s.tool == InkTool.highlighter;
    final paint = Paint()
      ..color = hl ? color.withValues(alpha: 0.35) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width
      ..strokeCap = hl ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = hl ? BlendMode.multiply : BlendMode.srcOver;
    final pts = s.points;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, s.width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(NotebookInkPainter old) => true;
}
