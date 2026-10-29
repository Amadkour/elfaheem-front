// Visual review renders of D-096 (the whiteboard's hand tool and edge auto-scroll; compared by eye, NOT a CI suite):
//
//   flutter test test/visual/whiteboard_hand_golden_test.dart --update-goldens
//
// → test/visual/goldens/hand_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   room   the presenter's continuous board with the hand on, the mouse over the hand (its tooltip), scrolled down
//          by a drag of the hand.
//   draw   the pen held near the bottom edge: the page scrolled up under it, the stroke followed.
//   dock   the dock on its own: the hand selected, the select tool (the mouse pointer) selected, narrow and wide.
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart' show WhiteboardStage;
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
bool get _ar => AppConfig.lang == 'ar';
String _tr(String ar, String en) => _ar ? ar : en;

Widget _host(Widget Function(BuildContext) scene, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      // The shot holds the Navigator: the tooltip is in its overlay.
      builder: (context, w) => RepaintBoundary(
          key: _shot, child: Directionality(textDirection: _ar ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: scene),
    ),
  );
}

Widget _room(BuildContext context, Widget stage) {
  LivePalette.sync(context);
  return Theme(
    data: ThemeData(brightness: Brightness.dark, fontFamily: AppFonts.family), // the tooltip's text too
    child: Scaffold(
      backgroundColor: LivePalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(0, -0.3), radius: 1.2, colors: [LivePalette.surfaceHi, LivePalette.bg]),
              ),
              child: stage,
            ),
          ),
        ),
      ),
    ),
  );
}

final _controllers = <BoardController>[];
final _memo = <String, Object>{};
T _once<T extends Object>(String key, T Function() create) => _memo.putIfAbsent(key, create) as T;

const _len = kBoardContinuousLength;
Offset _w(double x, double yW) => Offset(x, yW / _len);

void _ink(BoardController c, List<Offset> pts, {bool highlighter = false}) {
  c.beginInk(pts.first.dx, pts.first.dy, highlighter: highlighter);
  for (final p in pts.skip(1)) {
    c.moveInk(p.dx, p.dy);
  }
  c.endInk();
}

void _shape(BoardController c, BoardShapeKind k, Offset a, Offset b) {
  c.beginShape(k, a.dx, a.dy);
  c.moveShape(b.dx, b.dy);
  c.endShape();
}

void _text(BoardController c, Offset at, String text, {int font = 1, double width = 0.86}) {
  c.setFontStep(font);
  final id = c.createText(at.dx, at.dy, boxWidth: width)!;
  c.updateText(id, text: text);
  c.endEdit(id);
}

/// A continuous lined board with three screens of a lesson.
BoardController _lesson(BoardTool tool) {
  final t = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 'h', isHost: (i) => i == 'teacher_1');
  _controllers.add(t);
  t.startPresenting(background: BoardBackground.lined, format: BoardFormat.continuous);
  final ink = boardInkColors(BoardBackground.lined);
  t.setColor(ink[0].toARGB32());
  _text(t, _w(0.07, 0.06), _tr('الفصل الثالث · المشتقات', 'Chapter 3 · Derivatives'), font: 3);
  _text(t, _w(0.07, 0.2), _tr('المشتقة تقيس سرعة تغيّر الدالة عند كل نقطة.', 'The derivative measures how fast a function changes at each point.'));
  t.setColor(ink[1].toARGB32());
  _text(t, _w(0.07, 0.38), "f'(x) = lim (f(x+h) − f(x)) / h", font: 2);
  t.setColor(ink[4].toARGB32());
  _ink(t, [for (var i = 0; i <= 30; i++) _w(0.07 + i * 0.026, 0.43 + math.sin(i * 0.5) * 0.004)], highlighter: true);
  t.setColor(ink[0].toARGB32());
  _shape(t, BoardShapeKind.arrow, _w(0.1, 1.15), _w(0.9, 1.15));
  _shape(t, BoardShapeKind.arrow, _w(0.15, 1.2), _w(0.15, 0.6));
  t.setColor(ink[1].toARGB32());
  t.setThickness(2);
  _ink(t, [for (var i = 0; i <= 50; i++) _w(0.18 + i * 0.014, 1.1 - math.pow(i / 50, 2) * 0.42)]);
  t.setThickness(1);
  t.setColor(ink[2].toARGB32());
  _shape(t, BoardShapeKind.line, _w(0.42, 1.08), _w(0.86, 0.72));
  _text(t, _w(0.6, 0.66), _tr('المماس', 'tangent'), width: 0.3);
  t.setColor(ink[0].toARGB32());
  _text(t, _w(0.07, 1.36), _tr('مثال ١', 'Example 1'), font: 2, width: 0.6);
  _text(t, _w(0.07, 1.5), 'f(x) = x³ − 2x', font: 2, width: 0.6);
  _text(t, _w(0.07, 1.66), "f'(x) = 3x² − 2", font: 2, width: 0.6);
  t.setColor(ink[3].toARGB32());
  _shape(t, BoardShapeKind.rect, _w(0.05, 1.63), _w(0.62, 1.77));
  t.setColor(ink[0].toARGB32());
  t.select(null);
  t.setTool(tool);
  return t;
}

Widget _roomScene(BuildContext context) {
  final c = _once('room', () => _lesson(BoardTool.hand));
  return _room(context, WhiteboardRoomView(controller: c, fallbackRtl: _ar, onStop: () {}, onOptions: () {}, keyboard: false));
}

/// Drags the page up with the hand (the mouse), then rests the mouse on the hand: its tooltip.
Future<void> _panThenHover(WidgetTester t) async {
  final stage = t.getRect(find.byType(WhiteboardStage));
  final narrow = stage.width < 600;
  final g = await t.startGesture(stage.center, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await g.moveBy(Offset(0, narrow ? -30.0 : -34.0));
  }
  await g.up();
  await t.pump();
  await g.removePointer();
  final hover = await t.createGesture(kind: PointerDeviceKind.mouse);
  await hover.addPointer(location: Offset.zero);
  await hover.moveTo(t.getCenter(find.byKey(const ValueKey('board.tool.hand'))));
  await t.pump(const Duration(seconds: 1));
}

Widget _drawScene(BuildContext context) {
  final c = _once('draw', () {
    final c = _lesson(BoardTool.pen);
    c.setColor(boardInkColors(BoardBackground.lined)[2].toARGB32());
    c.setThickness(2);
    return c;
  });
  return _room(context, WhiteboardRoomView(controller: c, fallbackRtl: _ar, onStop: () {}, onOptions: () {}, keyboard: false));
}

/// Writes a wavy line down to the bottom edge and holds the pen there a moment (the page scrolls up under it).
Future<void> _drawToEdge(WidgetTester t) async {
  final stage = t.getRect(find.byType(WhiteboardStage));
  final from = Offset(stage.left + stage.width * 0.3, stage.top + stage.height * 0.55);
  final to = Offset(stage.left + stage.width * 0.55, stage.bottom - 8);
  final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 16; i++) {
    await t.pump(const Duration(milliseconds: 16));
    final p = Offset.lerp(from, to, i / 16)!;
    await g.moveTo(p + Offset(math.sin(i * 0.8) * 10, 0));
  }
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  // Still held: the dock stays as it is while drawing.
}

Widget _dockScene(BuildContext context) {
  LivePalette.sync(context);
  final narrow = MediaQuery.sizeOf(context).width < 700;
  final colors = boardInkColors(BoardBackground.white);
  Widget dock(BoardTool tool, {bool wide = false}) => WhiteboardToolbar(
        tool: tool,
        color: colors.first,
        colors: colors,
        colorLabels: boardColorLabels(BoardBackground.white),
        thickness: 1,
        fontStep: 1,
        canUndo: true,
        canRedo: false,
        wide: wide,
        onTool: (_) {},
        onColor: (_) {},
        onThickness: (_) {},
        onFontStep: (_) {},
        onUndo: () {},
        onRedo: () {},
        onPanel: (_) {},
      );
  Widget label(String s) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(s, style: appText(12, w: FontWeight.w600, c: LivePalette.textMid)),
      );
  return Theme(
    data: ThemeData(brightness: Brightness.dark, fontFamily: AppFonts.family), // the tooltip's text too
    child: Scaffold(
      backgroundColor: LivePalette.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: narrow
              ? Center(
                  child: SizedBox(
                    width: 366,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      label(_tr('اليد مختارة', 'Hand selected')),
                      dock(BoardTool.hand),
                      label(_tr('التحديد (مؤشر الفأرة) مختار', 'Select (the mouse pointer) selected')),
                      dock(BoardTool.select),
                      label(_tr('القلم مختار', 'Pen selected')),
                      dock(BoardTool.pen),
                    ]),
                  ),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label(_tr('اليد مختارة', 'Hand selected')),
                  dock(BoardTool.hand, wide: true),
                  const SizedBox(height: 8),
                  label(_tr('التحديد (مؤشر الفأرة) مختار', 'Select (the mouse pointer) selected')),
                  dock(BoardTool.select, wide: true),
                  const SizedBox(height: 8),
                  label(_tr('على الجهاز اللوحي: صفّان', 'On a tablet: two rows')),
                  SizedBox(width: 420, child: dock(BoardTool.hand)),
                ]),
        ),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(BuildContext) scene,
    {Future<void> Function(WidgetTester t)? act, List<bool> themes = const [true]}) async {
  final prevLang = AppConfig.lang;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in themes) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          for (final c in _controllers) {
            c.dispose();
          }
          _controllers.clear();
          _memo.clear();
          await tester.pumpWidget(_host(scene, dark: dark));
          await tester.pump(const Duration(milliseconds: 100));
          if (act != null) await act(tester);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/hand_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    AppConfig.disableList = [];
    DrawInputPrefs.offered = true; // no "Stylus only?" banner over the renders
  });

  testWidgets('room', (t) => _render(t, 'room', _roomScene, act: _panThenHover, themes: const [false, true]));
  testWidgets('draw', (t) => _render(t, 'draw', _drawScene, act: _drawToEdge));
  testWidgets('dock', (t) => _render(t, 'dock', _dockScene));
}
