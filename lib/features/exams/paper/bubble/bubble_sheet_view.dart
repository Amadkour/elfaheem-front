// The sheet with the detection drawn over it: every block coloured by what it is (answers, the student ID, left out),
// anything unsure ringed in amber, a pin where the teacher tapped. Zoom and pan with two fingers or the mouse; a tap
// is reported as a fraction of the sheet, so the server's coordinates never see the screen. Plain values in, a tap out.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_flow.dart';

class BubbleSheetView extends StatelessWidget {
  const BubbleSheetView({
    super.key,
    required this.image,
    required this.aspect,
    required this.blocks,
    this.unsure = const [],
    this.taps = const [],
    this.questions = const [],
    this.onTap,
    this.onDragBox,
    this.semanticLabel,
  });

  final Uint8List? image;

  /// height / width of the sheet.
  final double aspect;
  final List<BubbleBlock> blocks;
  final List<BubbleUnsure> unsure;
  final List<BubbleTap> taps;
  final void Function(Offset fraction)? onTap;

  /// The numbered questions (D-500), drawn with each choice's letter.
  final List<BubbleQuestionMark> questions;

  /// Set while the teacher drags the student-ID box: the drag is reported as fractions of the sheet.
  final void Function(Rect fractions)? onDragBox;
  final String? semanticLabel;

  Widget _stack(dynamic c, double w, double h) => Stack(children: [
        Positioned.fill(
          child: image != null
              ? Image.memory(image!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium)
              : DecoratedBox(decoration: BoxDecoration(color: c.cardBg as Color)),
        ),
        Positioned.fill(child: CustomPaint(painter: _SheetPainter(blocks: blocks, unsure: unsure, taps: taps, questions: questions, colors: _Palette.of(c)))),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = (w * aspect).clamp(240.0, 2000.0);
      if (onDragBox != null) {
        return _DragBoxSheet(width: w, height: h, onDone: onDragBox!, child: _stack(c, w, h));
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: w,
          height: h,
          color: c.inputBg,
          child: Semantics(
            label: semanticLabel ?? t('الورقة مع ما تم اكتشافه', 'The sheet with what was detected'),
            child: InteractiveViewer(
              maxScale: 5,
              minScale: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onTap == null
                    ? null
                    : (d) {
                        final o = d.localPosition;
                        onTap!(Offset((o.dx / w).clamp(0.0, 1.0), (o.dy / h).clamp(0.0, 1.0)));
                      },
                child: _stack(c, w, h),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _DragBoxSheet extends StatefulWidget {
  const _DragBoxSheet({required this.width, required this.height, required this.onDone, required this.child});
  final double width, height;
  final void Function(Rect fractions) onDone;
  final Widget child;

  @override
  State<_DragBoxSheet> createState() => _DragBoxSheetState();
}

class _DragBoxSheetState extends State<_DragBoxSheet> {
  Offset? _a, _b;

  Rect? get _rect => _a == null || _b == null ? null : Rect.fromPoints(_a!, _b!);

  Offset _clamp(Offset o) => Offset(o.dx.clamp(0.0, widget.width), o.dy.clamp(0.0, widget.height));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _rect;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => setState(() {
            _a = _clamp(d.localPosition);
            _b = _a;
          }),
          onPanUpdate: (d) => setState(() => _b = _clamp(d.localPosition)),
          onPanEnd: (_) {
            final box = _rect;
            if (box != null && box.width > 12 && box.height > 12) {
              widget.onDone(Rect.fromLTWH(box.left / widget.width, box.top / widget.height, box.width / widget.width, box.height / widget.height));
            }
            setState(() {
              _a = null;
              _b = null;
            });
          },
          child: Stack(children: [
            Positioned.fill(child: widget.child),
            if (r != null)
              Positioned.fromRect(
                rect: r,
                child: DecoratedBox(decoration: BoxDecoration(color: c.accent2.withValues(alpha: 0.18), border: Border.all(color: c.accent2, width: 2), borderRadius: BorderRadius.circular(AppRadius.chip))),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette({required this.answers, required this.identifier, required this.ignored, required this.unsure, required this.tap, required this.onAnswers});
  final Color answers, identifier, ignored, unsure, tap, onAnswers;

  static _Palette of(dynamic c) => _Palette(answers: c.primary as Color, identifier: c.accent2 as Color, ignored: c.textLight as Color, unsure: c.warning as Color, tap: c.danger as Color, onAnswers: c.onHero as Color);
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({required this.blocks, required this.unsure, required this.taps, required this.colors, this.questions = const []});
  final List<BubbleBlock> blocks;
  final List<BubbleUnsure> unsure;
  final List<BubbleTap> taps;
  final List<BubbleQuestionMark> questions;
  final _Palette colors;

  Color _roleColor(String role) => switch (role) {
        'identifier' => colors.identifier,
        'ignore' => colors.ignored,
        _ => colors.answers,
      };

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in blocks) {
      if (b.box.length != 4) continue;
      final col = _roleColor(b.role);
      final r = Rect.fromLTWH(b.box[0] * size.width, b.box[1] * size.height, b.box[2] * size.width, b.box[3] * size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(8)), Paint()..color = col.withValues(alpha: b.role == 'ignore' ? 0.05 : 0.10));
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = col.withValues(alpha: b.role == 'ignore' ? 0.5 : 0.9));
      final dot = Paint()..color = col.withValues(alpha: 0.55);
      for (final row in b.cells) {
        for (final p in row) {
          canvas.drawCircle(Offset(p[0] * size.width, p[1] * size.height), 2.2, dot);
        }
      }
    }
    _paintQuestions(canvas, size);
    for (final u in unsure) {
      final box = u.box;
      if (box == null || box.length != 4) continue;
      final r = Rect.fromLTWH(box[0] * size.width, box[1] * size.height, box[2] * size.width, box[3] * size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(10)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..color = colors.unsure);
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(10)), Paint()..color = colors.unsure.withValues(alpha: 0.12));
    }
    for (final tp in taps) {
      final o = Offset(tp.x * size.width, tp.y * size.height);
      canvas.drawCircle(o, 12, Paint()..color = colors.tap.withValues(alpha: 0.22));
      canvas.drawCircle(o, 5, Paint()..color = colors.tap);
    }
  }

  void _label(Canvas canvas, String text, Offset centre, double fontSize, Color color, {Color? halo}) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontFamily: AppFonts.family, fontSize: fontSize, fontWeight: FontWeight.w800, color: color)), textDirection: TextDirection.ltr)..layout();
    final o = centre - Offset(tp.width / 2, tp.height / 2);
    if (halo != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 3, o.dy - 1, tp.width + 6, tp.height + 2), const Radius.circular(4)), Paint()..color = halo);
    }
    tp.paint(canvas, o);
  }

  /// Each question's number beside its first choice, each choice's letter on its bubble.
  void _paintQuestions(Canvas canvas, Size size) {
    if (questions.isEmpty) return;
    final scale = (size.width / 620.0).clamp(0.55, 1.3);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = colors.answers;
    for (final q in questions) {
      if (q.cells.isEmpty) continue;
      final pts = [for (final p in q.cells) Offset(p[0] * size.width, p[1] * size.height)];
      final radius = pts.length > 1 ? ((pts[1] - pts[0]).distance * 0.36).clamp(4.0, 16.0) : 8.0;
      for (final (i, o) in pts.indexed) {
        canvas.drawCircle(o, radius, ring);
        if (i < q.labels.length) _label(canvas, q.labels[i], o, 8.5 * scale, colors.answers);
      }
      final first = pts.first;
      final dir = pts.length > 1 ? (first - pts[1]) / (first - pts[1]).distance : const Offset(-1, 0);
      _label(canvas, '${q.n}', first + dir * (radius + 11 * scale), 10 * scale, colors.onAnswers, halo: colors.answers);
    }
  }

  @override
  bool shouldRepaint(_SheetPainter o) => o.blocks != blocks || o.unsure != unsure || o.taps != taps || o.colors != colors || o.questions != questions;
}

/// The legend under the sheet.
class BubbleSheetLegend extends StatelessWidget {
  const BubbleSheetLegend({super.key, this.showUnsure = true});
  final bool showUnsure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget one(Color col, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: AppIconSize.xs, height: AppIconSize.xs, decoration: BoxDecoration(color: col.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: col))),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(label, style: AppType.meta(context))),
        ]);
    return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
      one(c.primary, t('الأسئلة', 'Questions')),
      one(c.accent2, t('رقم الطالب', 'Student ID')),
      one(c.textLight, t('مستبعد', 'Left out')),
      if (showUnsure) one(c.warning, t('يحتاج تأكيدًا', 'Unsure')),
    ]);
  }
}
