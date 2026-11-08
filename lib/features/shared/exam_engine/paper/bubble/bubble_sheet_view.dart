// The sheet with the detection drawn over it: every block coloured by what it is (answers, the student ID, left out),
// anything unsure ringed in amber, a pin where the teacher tapped. Zoom and pan with two fingers or the mouse; a tap
// is reported as a fraction of the sheet, so the server's coordinates never see the screen. Plain values in, a tap out.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import 'bubble_flow.dart';

class BubbleSheetView extends StatelessWidget {
  const BubbleSheetView({
    super.key,
    required this.image,
    required this.aspect,
    required this.blocks,
    this.unsure = const [],
    this.taps = const [],
    this.onTap,
    this.semanticLabel,
  });

  final Uint8List? image;

  /// height / width of the sheet.
  final double aspect;
  final List<BubbleBlock> blocks;
  final List<BubbleUnsure> unsure;
  final List<BubbleTap> taps;
  final void Function(Offset fraction)? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = (w * aspect).clamp(240.0, 2000.0);
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
                child: Stack(children: [
                  Positioned.fill(
                    child: image != null
                        ? Image.memory(image!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium)
                        : DecoratedBox(decoration: BoxDecoration(color: c.cardBg)),
                  ),
                  Positioned.fill(child: CustomPaint(painter: _SheetPainter(blocks: blocks, unsure: unsure, taps: taps, colors: _Palette.of(c)))),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Palette {
  const _Palette({required this.answers, required this.identifier, required this.ignored, required this.unsure, required this.tap});
  final Color answers, identifier, ignored, unsure, tap;

  static _Palette of(dynamic c) => _Palette(answers: c.primary as Color, identifier: c.accent2 as Color, ignored: c.textLight as Color, unsure: c.warning as Color, tap: c.danger as Color);
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({required this.blocks, required this.unsure, required this.taps, required this.colors});
  final List<BubbleBlock> blocks;
  final List<BubbleUnsure> unsure;
  final List<BubbleTap> taps;
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

  @override
  bool shouldRepaint(_SheetPainter o) => o.blocks != blocks || o.unsure != unsure || o.taps != taps || o.colors != colors;
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
