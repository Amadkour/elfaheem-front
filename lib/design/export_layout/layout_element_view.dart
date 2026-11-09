// lib/design/export_layout/layout_element_view.dart
//
// How the app draws a v3 element, a row card and a band — on the studio canvas (scale = screen px per mm from
// StudioCanvas.scaleOf) and in the live row preview (real items, rules applied). The FILE is drawn by the server;
// this only has to look like it: text is clipped to its box (ellipsis with max_lines), as the renderer does.
//
//   LayoutElementView   one element for one item (or the design view: field names in brackets)
//   LayoutBoxView       a card / band: its elements placed in mm at [scale], background, border, radius
//   LayoutAssets        image bytes uploaded in this session (asset id → bytes), so the canvas can show them
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../export/export_fonts.dart' show ExportFonts;
import '../export_hub/export_designer.dart' show exportFlutterFont, exportFlutterFallback;
import 'layout_logic.dart';
import 'layout_model.dart';

/// 1 pt in millimetres.
const double kPtMm = 25.4 / 72;

/// Screen pixels per millimetre at 100 %.
const double kMmPx = 96 / 25.4;

/// The images this session uploaded (the server knows them by id; the canvas draws the bytes).
abstract final class LayoutAssets {
  static final Map<String, Uint8List> _bytes = {};
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Uint8List? of(String? id) => id == null ? null : _bytes[id];

  static void put(String id, Uint8List bytes) {
    _bytes[id] = bytes;
    version.value++;
  }
}

/// `#RRGGBB` / `#AARRGGBB` → Color ([fallback] when empty or malformed).
Color? layoutColor(String? hex, [Color? fallback]) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// A shadow colour as the model stores it: `#RRGGBB` (opaque) or `#AARRGGBB` — the contract's one colour order, the
/// same [layoutColor] and the server read (the default `#55000000` is black at a third).
Color layoutShadowColor(String? hex) => layoutColor(hex, const Color(0x55000000))!;

/// [c] as a shadow colour string `#AARRGGBB`.
String layoutShadowHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

String layoutHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The icons a rule may put before its text (`then.icon`) — exactly the server's set (model.py `ICONS`): it drops
/// any other name, so the app neither offers nor draws one.
const kLayoutRuleIcons = <String, IconData>{
  'check': Icons.check_circle_rounded,
  'x': Icons.cancel_rounded,
  'dot': Icons.circle,
  'star': Icons.star_rounded,
  'warning': Icons.warning_amber_rounded,
};

/// The sample variables the canvas and the row preview show (the server fills the real ones).
Map<String, String> layoutSampleVars({required String lang, String title = '', String org = '', int total = 0, String filters = ''}) => {
      'date': () {
        final n = DateTime.now();
        return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
      }(),
      'exporter': lang == 'ar' ? 'أنت' : 'You',
      'org_name': org,
      'total': '$total',
      'page': '1',
      'pages': '3',
      'title': title,
      'filters': filters,
      'group': lang == 'ar' ? 'المجموعة' : 'Group',
    };

/// The text style of [e] at [scale] screen px per mm: the design's font and size (the page's [pageFont] /
/// [pageFontSize] when the element has none), pt → mm; [bold] = a rule's override of the weight.
TextStyle layoutTextStyle(LayoutElement e, String pageFont, double scale, Color color, {double pageFontSize = 10, bool? bold}) {
  final s = e.style;
  final fontId = s.font ?? pageFont;
  // the renderer draws italic with the family's own italic file when it has one (fonts.py pdf_font, not when bold)
  final wantBold = bold ?? s.bold;
  final family = s.italic && !wantBold && ExportFonts.has('${fontId}_italic') ? '${fontId}_italic' : fontId;
  final sh = s.shadow;
  final textual = e.kind == 'text' || e.kind == 'field' || e.kind == 'badge' || e.kind == 'page_number';
  return TextStyle(
    fontFamily: exportFlutterFont(family),
    fontFamilyFallback: exportFlutterFallback(family),
    fontSize: ((s.size ?? pageFontSize) * kPtMm * scale).clamp(1.0, 400.0),
    fontWeight: (bold ?? s.bold) ? FontWeight.w700 : FontWeight.w400,
    fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
    color: color,
    height: s.lineHeight <= 0 ? 1.3 : s.lineHeight,
    letterSpacing: s.letterSpacing == 0 ? null : s.letterSpacing * kPtMm * scale,
    shadows: sh == null || !textual ? null : [Shadow(color: layoutShadowColor(sh.color), offset: Offset(sh.dx * scale, sh.dy * scale), blurRadius: .6 * scale)],
  );
}

/// One element in its box (the caller sizes the box).
class LayoutElementView extends StatelessWidget {
  const LayoutElementView({
    super.key,
    required this.element,
    required this.scale,
    required this.rtl,
    required this.pageFont,
    this.pageFontSize = 10,
    this.item,
    this.index = 1,
    this.lang = 'en',
    this.vars = const {},
    this.fieldOf,
    this.ghostHidden = false,
  });

  final LayoutElement element;

  /// Screen pixels per millimetre.
  final double scale;
  final bool rtl;
  final String pageFont;

  /// The page's text size (pt): an element with no size of its own.
  final double pageFontSize;

  /// The item to show; null = the design view (a bound field shows its name in brackets).
  final Map<String, Object?>? item;
  final int index;
  final String lang;
  final Map<String, String> vars;
  final LayoutField? Function(String key)? fieldOf;

  /// Draw an element its rules hide faintly (the canvas) instead of not at all (the preview).
  final bool ghostHidden;

  String _designText() {
    final e = element;
    if (e.computed != null) {
      return e.computed!.op == 'index' ? '#' : '[${e.computed!.fields.map((f) => fieldOf?.call(f)?.label(lang) ?? f).join(e.computed!.sep)}]';
    }
    if (e.bind != null) return '${e.bind!.prefix}[${fieldOf?.call(e.bind!.field)?.label(lang) ?? e.bind!.field}]${e.bind!.suffix}';
    return layoutFillVars(e.value ?? '', vars);
  }

  @override
  Widget build(BuildContext context) {
    final e = element;
    final s = e.style;
    LayoutResolved r;
    if (item == null) {
      r = LayoutResolved(show: true, text: _designText());
    } else {
      r = layoutResolve(e, item!, index: index, lang: lang, vars: vars, fieldOf: fieldOf);
    }
    if (!r.show && !ghostHidden) return const SizedBox.shrink();
    final color = layoutColor(r.color ?? s.color, const Color(0xFF1A1A1A))!;
    final bg = layoutColor(r.bg ?? s.bg);
    final border = s.border;
    final radius = BorderRadius.circular(s.radius * scale);
    Widget child;
    switch (e.kind) {
      case 'line':
        final b = border ?? LayoutBorder(width: 0.3, color: s.color);
        // through the middle of its box: horizontal when w >= h, else vertical
        final thick = (b.width * scale).clamp(1.0, 40.0).toDouble();
        final ink = layoutColor(b.color, color);
        child = Center(
          child: element.w >= element.h ? Container(height: thick, color: ink) : Container(width: thick, color: ink),
        );
        return Opacity(opacity: (r.show ? 1 : .25) * e.opacity, child: child);
      case 'rect':
        child = const SizedBox.expand();
      case 'ellipse':
        return Opacity(
          opacity: (r.show ? 1 : .25) * e.opacity,
          child: CustomPaint(
            painter: LayoutOvalPainter(
              fill: bg,
              stroke: border == null || border.width <= 0 ? null : layoutColor(border.color, color),
              strokeWidth: border == null ? 0 : (border.width * scale).clamp(.5, 20.0).toDouble(),
              shadow: s.shadow == null ? null : layoutShadowColor(s.shadow!.color),
              shadowOffset: s.shadow == null ? Offset.zero : Offset(s.shadow!.dx * scale, s.shadow!.dy * scale),
            ),
            child: const SizedBox.expand(),
          ),
        );
      case 'image' || 'signature':
        child = _image(context, color);
      case 'qr':
        child = FittedBox(child: Icon(Icons.qr_code_2_rounded, color: color));
      default:
        child = _text(r, color);
    }
    final sh = s.shadow;
    child = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        boxShadow: sh == null || !(e.kind == 'rect' || e.kind == 'image' || e.kind == 'signature')
            ? null
            : [BoxShadow(color: layoutShadowColor(sh.color), offset: Offset(sh.dx * scale, sh.dy * scale), blurRadius: .6 * scale)],
        border: border == null || border.width <= 0 ? null : Border.all(color: layoutColor(border.color, color)!, width: (border.width * scale).clamp(.5, 20.0)),
      ),
      clipBehavior: bg == null && border == null ? Clip.hardEdge : Clip.antiAlias,
      padding: EdgeInsets.all((s.padding * scale).clamp(0.0, 40.0)),
      child: child,
    );
    return Opacity(opacity: (r.show ? 1 : .25) * e.opacity, child: child);
  }

  TextStyle _style(Color color, [bool? bold]) => layoutTextStyle(element, pageFont, scale, color, pageFontSize: pageFontSize, bold: bold);

  Widget _text(LayoutResolved r, Color color) {
    final s = element.style;
    final dir = switch (s.dir) {
      'rtl' => TextDirection.rtl,
      'ltr' => TextDirection.ltr,
      // auto (the server's rule): right-to-left only for Arabic text on a right-to-left page
      _ => rtl && _hasArabic(r.text) ? TextDirection.rtl : TextDirection.ltr,
    };
    // start / end follow the PAGE direction (physical), whatever the text's own direction
    final h = switch (s.align) {
      'center' => 0.0,
      'end' => rtl ? -1.0 : 1.0,
      _ => rtl ? 1.0 : -1.0,
    };
    final v = switch (s.valign) {
      'top' => -1.0,
      'bottom' => 1.0,
      _ => 0.0,
    };
    final icon = kLayoutRuleIcons[r.icon];
    final maxLines = s.maxLines > 0 ? s.maxLines : (s.wrap ? null : 1);
    final align = h == 0 ? TextAlign.center : (h < 0 ? TextAlign.left : TextAlign.right);
    Widget body(TextStyle style) {
      final text = Text(
        r.text,
        style: style,
        textDirection: dir,
        textAlign: align,
        maxLines: maxLines,
        overflow: s.maxLines > 0 ? TextOverflow.ellipsis : TextOverflow.clip,
        softWrap: s.wrap,
      );
      return Directionality(
        textDirection: dir,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment(h, v),
            maxHeight: double.infinity,
            child: Align(
              alignment: Alignment(h, v),
              child: icon == null
                  ? text
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: style.fontSize! * 1.1, color: color),
                      SizedBox(width: style.fontSize! * .25),
                      Flexible(child: text),
                    ]),
            ),
          ),
        ),
      );
    }

    final style = _style(color, r.bold);
    if (!s.shrink) return body(style);
    // shrink to fit: the font goes down (to 50 %) until the text fits the box, instead of being clipped
    return LayoutBuilder(builder: (context, box) {
      final f = layoutShrinkFactor(
        text: r.text,
        style: style,
        dir: dir,
        maxWidth: box.maxWidth,
        maxHeight: box.maxHeight,
        maxLines: maxLines,
        wrap: s.wrap,
      );
      return body(f >= 1 ? style : style.copyWith(fontSize: style.fontSize! * f, letterSpacing: style.letterSpacing == null ? null : style.letterSpacing! * f));
    });
  }

  static bool _hasArabic(String s) => s.runes.any((r) => (r >= 0x0600 && r <= 0x08FF) || (r >= 0xFB50 && r <= 0xFEFC));

  Widget _image(BuildContext context, Color color) {
    final e = element;
    final fit = switch (e.fit) {
      'cover' => BoxFit.cover,
      'fill' => BoxFit.fill,
      _ => BoxFit.contain,
    };
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // decode at the size it is drawn at (a 12 MP photo in a 40 px box would otherwise cost tens of MB)
    final cacheW = (e.w * scale * dpr).round().clamp(16, 2048);
    // an image can arrive after the canvas built (fetched in the background): it must replace the placeholder then
    Widget picture = ValueListenableBuilder<int>(
      valueListenable: LayoutAssets.version,
      builder: (context, _, _) {
        final bytes = LayoutAssets.of(e.value);
        return bytes != null
            ? Image.memory(bytes, fit: fit, gaplessPlayback: true, cacheWidth: cacheW)
            : Container(
                color: const Color(0x0F101828),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(e.kind == 'signature' ? Icons.draw_rounded : Icons.image_outlined, color: const Color(0xFF98A2B3)),
                  ),
                ),
              );
      },
    );
    picture = layoutShapeClip(e.shape, picture);
    if (e.kind != 'signature') return picture;
    final small = _style(color).copyWith(fontSize: ((e.style.size ?? pageFontSize) * .9 * kPtMm * scale).clamp(1.0, 200.0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: picture),
      if ((e.sigName ?? '').isNotEmpty) Text(layoutFillVars(e.sigName!, vars), style: small.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip),
      if ((e.sigTitle ?? '').isNotEmpty) Text(layoutFillVars(e.sigTitle!, vars), style: small, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip),
    ]);
  }
}

/// Clips [child] to an image [shape]: rect | rounded (a tenth of the shorter side) | circle (an ellipse in a
/// non-square box; the server crops photos to a circle in a square box).
Widget layoutShapeClip(String shape, Widget child) => switch (shape) {
      'circle' => ClipOval(child: child),
      'rounded' => LayoutRoundedClip(child: child),
      _ => child,
    };

/// A rounded clip whose radius follows the box: a tenth of the shorter side.
class LayoutRoundedClip extends StatelessWidget {
  const LayoutRoundedClip({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final side = box.hasBoundedWidth && box.hasBoundedHeight ? math.min(box.maxWidth, box.maxHeight) : 40.0;
          return ClipRRect(borderRadius: BorderRadius.circular(side * .1), child: child);
        },
      );
}

/// The factor (1 down to .5) the font must be multiplied by for [text] to fit [maxWidth] x [maxHeight] in
/// [maxLines] lines (null = as many as needed), in steps of 5 %. 1 = it fits already (or the box is unbounded).
double layoutShrinkFactor({
  required String text,
  required TextStyle style,
  required TextDirection dir,
  required double maxWidth,
  required double maxHeight,
  int? maxLines,
  bool wrap = true,
}) {
  if (!maxWidth.isFinite || !maxHeight.isFinite || maxWidth <= 0 || maxHeight <= 0 || text.isEmpty) return 1;
  final base = style.fontSize ?? 14;
  for (var f = 1.0; f >= .5 - 1e-9; f -= .05) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: base * f, letterSpacing: style.letterSpacing == null ? null : style.letterSpacing! * f),
      ),
      textDirection: dir,
      maxLines: maxLines,
    )..layout(maxWidth: wrap ? maxWidth : double.infinity);
    final fits = tp.height <= maxHeight + .5 && (wrap ? !tp.didExceedMaxLines : tp.width <= maxWidth + .5);
    tp.dispose();
    if (fits) return f;
  }
  return .5;
}

/// An ellipse filling its box: fill, outline and an offset shadow (the ellipse element).
class LayoutOvalPainter extends CustomPainter {
  const LayoutOvalPainter({this.fill, this.stroke, this.strokeWidth = 0, this.shadow, this.shadowOffset = Offset.zero});
  final Color? fill, stroke, shadow;
  final double strokeWidth;
  final Offset shadowOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final oval = strokeWidth > 0 && stroke != null ? box.deflate(strokeWidth / 2) : box;
    if (shadow != null && (fill != null || stroke != null)) {
      canvas.drawOval(oval.shift(shadowOffset), Paint()..color = shadow!..maskFilter = const MaskFilter.blur(BlurStyle.normal, .6));
    }
    if (fill != null) canvas.drawOval(oval, Paint()..color = fill!);
    if (stroke != null && strokeWidth > 0) {
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = stroke!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant LayoutOvalPainter old) =>
      old.fill != fill || old.stroke != stroke || old.strokeWidth != strokeWidth || old.shadow != shadow || old.shadowOffset != shadowOffset;
}

/// The page's background image under everything: an uploaded asset (drawn from the session's bytes) or an https URL,
/// laid out as [fit] (cover | contain | fill). Nothing (transparent) when the id has no bytes in this session.
class LayoutPageBackground extends StatelessWidget {
  const LayoutPageBackground({super.key, required this.image, this.fit = 'cover', this.cacheWidth});

  /// An asset id, or an https URL.
  final String? image;
  final String fit;

  /// Decode width in physical pixels (null = the image's own).
  final int? cacheWidth;

  static bool isUrl(String? v) => v != null && (v.startsWith('https://') || v.startsWith('http://'));

  @override
  Widget build(BuildContext context) {
    final id = image;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    final boxFit = switch (fit) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };
    if (isUrl(id)) {
      return SizedBox.expand(
        child: Image.network(id, fit: boxFit, cacheWidth: cacheWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: LayoutAssets.version,
      builder: (context, _, _) {
        final bytes = LayoutAssets.of(id);
        if (bytes == null) return const SizedBox.shrink();
        return SizedBox.expand(child: Image.memory(bytes, fit: boxFit, cacheWidth: cacheWidth, gaplessPlayback: true));
      },
    );
  }
}

/// A card of the row or a band, drawn at [scale] (px per mm) with its elements: the preview's building block.
class LayoutBoxView extends StatelessWidget {
  const LayoutBoxView({
    super.key,
    required this.elements,
    required this.width,
    required this.height,
    required this.scale,
    required this.rtl,
    required this.pageFont,
    this.pageFontSize = 10,
    this.item,
    this.index = 1,
    this.lang = 'en',
    this.vars = const {},
    this.fieldOf,
    this.background,
    this.border,
    this.radius = 0,
  });

  final List<LayoutElement> elements;

  /// mm
  final double width, height;
  final double scale;
  final bool rtl;
  final String pageFont;
  final double pageFontSize;
  final Map<String, Object?>? item;
  final int index;
  final String lang;
  final Map<String, String> vars;
  final LayoutField? Function(String key)? fieldOf;
  final String? background;
  final LayoutBorder? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final b = border;
    return Container(
      width: width * scale,
      height: height * scale,
      decoration: BoxDecoration(
        color: layoutColor(background, const Color(0xFFFFFFFF)),
        borderRadius: BorderRadius.circular(radius * scale),
        border: b == null || b.width <= 0 ? null : Border.all(color: layoutColor(b.color, const Color(0xFFD0D5DD))!, width: (b.width * scale).clamp(.5, 8.0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        for (final e in elements)
          Positioned(
            left: e.x * scale,
            top: e.y * scale,
            width: e.w * scale,
            height: e.h * scale,
            child: Transform.rotate(
              angle: e.rotation * 3.141592653589793 / 180,
              child: LayoutElementView(
                element: e,
                scale: scale,
                rtl: rtl,
                pageFont: pageFont,
                pageFontSize: pageFontSize,
                item: item,
                index: index,
                lang: lang,
                vars: vars,
                fieldOf: fieldOf,
              ),
            ),
          ),
      ]),
    );
  }
}
