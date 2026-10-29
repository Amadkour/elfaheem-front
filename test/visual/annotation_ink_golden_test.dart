// Visual review renders of the live-annotation ink (D-081), compared by eye like the other test/visual files:
//
//   flutter test test/visual/annotation_ink_golden_test.dart --update-goldens
//
// → test/visual/goldens/annotation_ink_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900. The SAME synthetic
// writing — drawn on a phone (a 360 px wide share view) at 120 Hz with digitiser jitter and a noisy stylus pressure,
// a finger underline, a finger circle, a highlighter zig-zag that crosses itself — is shown as a viewer on this
// screen size sees it: "Before" with the D-079 pipeline (raw samples, 4-decimal wire, a width per segment, RDP on
// lift), "After" with the real one (AnnotInkFilter → AnnotationController → AnnotationLayer / AnnotationPainter).
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_ink.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_layer.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_painter.dart' show AnnotFit;
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

const _frame = Size(1920, 1080);

/// The drawer's share view on a phone: 360 × 202.5 logical px.
const _drawer = Size(360, 202.5);

Future<void> _loadFonts() async {
  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    final loader = FontLoader(family);
    for (final p in assets) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }
}

/// One raw pointer sample in the drawer's px.
typedef _Raw = ({double x, double y, double t, double p});

class _Sketch {
  _Sketch(this.tool, this.raw, {this.stylus = false});

  final AnnotTool tool;
  final List<_Raw> raw;
  final bool stylus;
}

/// Samples [path] (normalised 0..1 → drawer px) at 120 Hz over [seconds], with jitter and pressure noise.
List<_Raw> _sample(Offset Function(double u) path, double seconds, math.Random r,
    {double jitter = 0.55, double Function(double u)? pressure, double pNoise = 0.14}) {
  final n = (seconds * 120).round();
  return [
    for (var i = 0; i <= n; i++)
      () {
        final u = i / n;
        final o = path(u);
        return (
          x: o.dx * _drawer.width + (r.nextDouble() * 2 - 1) * jitter,
          y: o.dy * _drawer.height + (r.nextDouble() * 2 - 1) * jitter,
          t: i / 120,
          p: pressure == null ? 0.5 : (pressure(u) + (r.nextDouble() * 2 - 1) * pNoise).clamp(0.0, 1.0),
        );
      }(),
  ];
}

List<_Sketch> _sketches() {
  final r = math.Random(29);
  // Cursive loops ("ℓℓℓℓ" — a prolate cycloid), written with a stylus.
  Offset loops(double u) {
    final a = u * 5 * 2 * math.pi;
    return Offset(0.08 + 0.52 * u + 0.035 * math.sin(a), 0.33 - 0.09 * math.cos(a) + 0.02 * u);
  }

  double profile(double u) => 0.25 + 0.5 * math.sin(math.pi * math.min(1, u * 1.15)).clamp(0.0, 1.0);
  // A finger underline, a little slower at the start.
  Offset underline(double u) => Offset(0.08 + 0.55 * (u * u * (3 - 2 * u)), 0.47 + 0.008 * math.sin(u * 3));
  // A finger circle around the formula.
  Offset circle(double u) {
    final a = -math.pi / 2 + u * 2.15 * math.pi;
    return Offset(0.79 + 0.11 * math.cos(a), 0.68 + 0.13 * math.sin(a));
  }

  // A highlighter zig-zag across a line of text: it crosses itself.
  Offset zig(double u) => Offset(0.08 + 0.42 * u, 0.73 + 0.06 * math.sin(u * 3 * math.pi));
  return [
    _Sketch(AnnotTool.pen, _sample(loops, 2.6, r, pressure: profile), stylus: true),
    _Sketch(AnnotTool.pen, _sample(underline, 0.9, r)),
    _Sketch(AnnotTool.pen, _sample(circle, 1.4, r)),
    _Sketch(AnnotTool.highlighter, _sample(zig, 1.1, r)),
  ];
}

/// The D-079 pipeline: raw samples on a 4-decimal grid, RDP when the pen lifts.
AnnotationController _before(List<_Sketch> s, List<int> colors) {
  num round4(double v) => (v * 10000).roundToDouble() / 10000;
  final c = AnnotationController(localIdentity: 'before', autoFlush: false);
  c.setRoles(hosts: {'before'});
  for (var i = 0; i < s.length; i++) {
    final k = s[i];
    c.setTool(k.tool);
    c.setColor(colors[i]);
    final pts = [
      for (final r in k.raw)
        AnnotPoint(round4(r.x / _drawer.width).toDouble(), round4(r.y / _drawer.height).toDouble(),
            k.stylus ? round4(r.p).toDouble() : 0.5),
    ];
    final simplified = annotSimplify(pts);
    c.begin(simplified.first.x, simplified.first.y, p: simplified.first.p, stylus: k.stylus);
    for (final p in simplified.skip(1)) {
      c.move(p.x, p.y, p: p.p);
    }
    c.end();
  }
  return c;
}

/// The D-081 pipeline, exactly as the layer runs it.
AnnotationController _after(List<_Sketch> s, List<int> colors) {
  final c = AnnotationController(localIdentity: 'after', autoFlush: false);
  c.setRoles(hosts: {'after'});
  for (var i = 0; i < s.length; i++) {
    final k = s[i];
    c.setTool(k.tool);
    c.setColor(colors[i]);
    final f = AnnotInkFilter(pressure: k.stylus);
    final first = f.start(k.raw.first.x, k.raw.first.y, k.raw.first.t, k.raw.first.p);
    c.begin(first.x / _drawer.width, first.y / _drawer.height, p: first.p, stylus: k.stylus);
    for (final r in k.raw.skip(1)) {
      final o = f.add(r.x, r.y, r.t, r.p);
      if (o != null) c.move(o.x / _drawer.width, o.y / _drawer.height, p: o.p);
    }
    final end = f.finish(k.raw.last.x, k.raw.last.y);
    if (end != null) c.move(end.x / _drawer.width, end.y / _drawer.height, p: end.p);
    c.end();
  }
  return c;
}

/// The shared slide: what the presenter's screen shows (drawn in frame coordinates through the contain fit).
class _SlidePainter extends CustomPainter {
  _SlidePainter(this.ink, this.muted, this.card);

  final Color ink;
  final Color muted;
  final Color card;

  @override
  void paint(Canvas canvas, Size size) {
    final r = AnnotFit.contain(_frame, size);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = card);
    void bar(double x, double y, double w, double h, Color c) => canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left + x * r.width, r.top + y * r.height, w * r.width, h * r.height), const Radius.circular(3)),
        Paint()..color = c);
    bar(0.08, 0.12, 0.42, 0.06, ink); // the title
    for (var i = 0; i < 3; i++) {
      bar(0.08, 0.56 + i * 0.09, 0.5 - i * 0.07, 0.035, muted); // lines of text
    }
    bar(0.68, 0.58, 0.22, 0.2, muted.withValues(alpha: 0.5)); // the formula box
  }

  @override
  bool shouldRepaint(_SlidePainter old) => false;
}

/// The D-079 renderer, as it was: a stylus stroke drawn segment by segment, each with its own width (0.5 + p) and
/// round caps; anything else one path.
class _LegacyPainter extends CustomPainter {
  _LegacyPainter(this.board);

  final AnnotBoard board;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = AnnotFit.contain(_frame, size);
    for (final s in board.strokes) {
      final pts = s.points;
      final hl = s.ink == AnnotInk.highlighter;
      final color = hl ? Color(s.color).withValues(alpha: 0.38) : Color(s.color);
      final base = math.max(1.0, s.width * rect.width);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = hl ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      final o = [for (final p in pts) AnnotFit.toLocal(p.x, p.y, rect)];
      final pressured = !hl && pts.any((p) => (p.p - 0.5).abs() > 0.02);
      if (!pressured) {
        paint.strokeWidth = base;
        canvas.drawPath(annotSmoothPath(o), paint);
        continue;
      }
      var from = o[0];
      for (var i = 1; i < o.length; i++) {
        final last = i == o.length - 1;
        final to = last ? o[i] : Offset((o[i].dx + o[i + 1].dx) / 2, (o[i].dy + o[i + 1].dy) / 2);
        paint.strokeWidth = base * (0.5 + pts[i].p);
        canvas.drawPath(
            Path()
              ..moveTo(from.dx, from.dy)
              ..quadraticBezierTo(o[i].dx, o[i].dy, to.dx, to.dy),
            paint);
        from = to;
      }
    }
  }

  @override
  bool shouldRepaint(_LegacyPainter old) => false;
}

Widget _stage(BuildContext context, AnnotationController c, {required bool legacy, bool padded = true}) {
  final colors = context.colors;
  return ClipRRect(
    borderRadius: BorderRadius.circular(padded ? 16 : 0),
    child: ColoredBox(
      color: LivePalette.bg,
      child: Padding(
        padding: EdgeInsets.all(padded ? 8 : 0),
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _SlidePainter(colors.charcoalDark, colors.textMedium.withValues(alpha: 0.35), colors.onHero)),
          if (legacy) CustomPaint(painter: _LegacyPainter(c.board)) else AnnotationLayer(controller: c, contentSize: _frame),
        ]),
      ),
    ),
  );
}

Widget _panel(BuildContext context, String title, String caption, AnnotationController c, {bool legacy = false}) {
  final colors = context.colors;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(caption, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMedium)),
      const SizedBox(height: 8),
      Expanded(flex: 5, child: _stage(context, c, legacy: legacy)),
      const SizedBox(height: 8),
      Text(t('تكبير ×4', 'Zoom ×4'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.textMedium)),
      const SizedBox(height: 4),
      Expanded(
        flex: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, box) => OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform.translate(
                // The first loops of the writing, four times larger: what a viewer on a big screen sees of a phone stroke.
                offset: Offset(-box.maxWidth * 0.52, -box.maxWidth * 4 * 9 / 16 * 0.21),
                child: SizedBox(
                  width: box.maxWidth * 4,
                  height: box.maxWidth * 4 * 9 / 16,
                  child: _stage(context, c, legacy: legacy, padded: false),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

Future<void> _render(WidgetTester tester) async {
  final prevLang = AppConfig.lang;
  final theme = ThemeConfigProvider(api: ApiClient());
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          final sketches = _sketches();
          final palette = [theme.danger, theme.danger, theme.purple, theme.warning].map((c) => c.toARGB32()).toList();
          final before = _before(sketches, palette);
          final after = _after(sketches, palette);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final shot = GlobalKey();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) =>
                  Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
              home: RepaintBoundary(
                key: shot,
                child: Builder(builder: (context) {
                  final wide = size.width >= 900;
                  final a = _panel(
                      context,
                      t('قبل', 'Before'),
                      t('العيّنات الخام، شبكة 4 منازل، عرض لكل مقطع، تبسيط عند الرفع',
                          'Raw samples, 4-decimal grid, a width per segment, simplified on lift'),
                      before,
                      legacy: true);
                  final b = _panel(
                      context,
                      t('بعد', 'After'),
                      t('مرشّح One Euro، 5 منازل، شكل واحد بعرض الضغط وأطراف مستدقّة',
                          'One Euro filter, 5 decimals, one shape with pressure width and tapered ends'),
                      after);
                  return Scaffold(
                    backgroundColor: context.colors.background,
                    appBar: AppBar(title: Text(t('حبر التعليق التوضيحي', 'Annotation ink'))),
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: wide
                          ? Row(children: [Expanded(child: a), const SizedBox(width: 24), Expanded(child: b)])
                          : Column(children: [Expanded(child: a), const SizedBox(height: 24), Expanded(child: b)]),
                    ),
                  );
                }),
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(shot),
            matchesGoldenFile('goldens/annotation_ink_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
          before.dispose();
          after.dispose();
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    AppFonts.setChoices(arabic: AppFonts.arabicDefault, latin: AppFonts.latinDefault);
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => AppConfig.disableList = []);
  testWidgets('annotation ink before / after', _render);
}
