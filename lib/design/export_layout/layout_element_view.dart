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

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
  final family = s.font ?? pageFont;
  return TextStyle(
    fontFamily: exportFlutterFont(family),
    fontFamilyFallback: exportFlutterFallback(family),
    fontSize: ((s.size ?? pageFontSize) * kPtMm * scale).clamp(1.0, 400.0),
    fontWeight: (bold ?? s.bold) ? FontWeight.w700 : FontWeight.w400,
    fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
    color: color,
    height: 1.15,
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
        return Opacity(opacity: r.show ? 1 : .25, child: child);
      case 'rect':
        child = const SizedBox.expand();
      case 'image' || 'signature':
        child = _image(context, color);
      case 'qr':
        child = FittedBox(child: Icon(Icons.qr_code_2_rounded, color: color));
      default:
        child = _text(r, color);
    }
    child = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border == null || border.width <= 0 ? null : Border.all(color: layoutColor(border.color, color)!, width: (border.width * scale).clamp(.5, 20.0)),
      ),
      clipBehavior: bg == null && border == null ? Clip.hardEdge : Clip.antiAlias,
      padding: EdgeInsets.all((s.padding * scale).clamp(0.0, 40.0)),
      child: child,
    );
    return Opacity(opacity: r.show ? 1 : .25, child: child);
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
    final style = _style(color, r.bold);
    final icon = kLayoutRuleIcons[r.icon];
    final text = Text(
      r.text,
      style: style,
      textDirection: dir,
      textAlign: h == 0 ? TextAlign.center : (h < 0 ? TextAlign.left : TextAlign.right),
      maxLines: s.maxLines > 0 ? s.maxLines : (s.wrap ? null : 1),
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

  static bool _hasArabic(String s) => s.runes.any((r) => (r >= 0x0600 && r <= 0x08FF) || (r >= 0xFB50 && r <= 0xFEFC));

  Widget _image(BuildContext context, Color color) {
    final e = element;
    final bytes = LayoutAssets.of(e.value);
    final fit = switch (e.fit) {
      'cover' => BoxFit.cover,
      'fill' => BoxFit.fill,
      _ => BoxFit.contain,
    };
    final picture = bytes != null
        ? Image.memory(bytes, fit: fit, gaplessPlayback: true)
        : Container(
            color: const Color(0x0F101828),
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(e.kind == 'signature' ? Icons.draw_rounded : Icons.image_outlined, color: const Color(0xFF98A2B3)),
              ),
            ),
          );
    if (e.kind != 'signature') return picture;
    final small = _style(color).copyWith(fontSize: ((e.style.size ?? pageFontSize) * .9 * kPtMm * scale).clamp(1.0, 200.0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: picture),
      if ((e.sigName ?? '').isNotEmpty) Text(layoutFillVars(e.sigName!, vars), style: small.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip),
      if ((e.sigTitle ?? '').isNotEmpty) Text(layoutFillVars(e.sigTitle!, vars), style: small, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip),
    ]);
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
