// Visual review renders of D-107 (a continuous whiteboard grows sideways; compared by eye, NOT a CI suite):
//
//   flutter test test/visual/whiteboard_grow_golden_test.dart --update-goldens
//
// → test/visual/goldens/grow_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   draw    the presenter holds the pen at the right edge: the page scrolled right and grew under the stroke; the
//           sideways rail shows the view at the page's new right end.
//   viewer  a viewer of a page grown both ways (a note left of the column, a worked example right of it), who dragged
//           the page away from the presenter: both rails with the presenter's marks, and "Follow …".
//   follow  the same viewer after "Follow …": back on the presenter's part of the page.
//   rails   (D-109) the same viewer following, both rails idle (the thumbs are scrollbars).
//   vgrab   the viewer long-pressed the vertical thumb and drags it down (still held: wide, accent, glow).
//   hgrab   the viewer long-pressed the sideways thumb and drags it left (still held).
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
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart' show WhiteboardStage;
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
      builder: (context, w) => RepaintBoundary(
          key: _shot, child: Directionality(textDirection: _ar ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: scene),
    ),
  );
}

Widget _room(BuildContext context, Widget stage) {
  LivePalette.sync(context);
  return Theme(
    data: ThemeData(brightness: Brightness.dark, fontFamily: AppFonts.family),
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
  c.select(null); // the next colour / thickness must not restyle it
}

void _text(BoardController c, Offset at, String text, {int font = 1, double width = 0.86}) {
  c.setFontStep(font);
  final id = c.createText(at.dx, at.dy, boxWidth: width)!;
  c.updateText(id, text: text);
  c.endEdit(id);
  c.select(null); // the next font step / colour must not restyle it
}

BoardController _teacher() {
  final t = BoardController(
    localIdentity: 'teacher_1',
    autoFlush: false,
    idPrefix: 'g',
    isHost: (i) => i == 'teacher_1',
    nameOf: (i) => _tr('د. منى السيد', 'Dr. Mona El-Sayed'),
  );
  _controllers.add(t);
  t.startPresenting(background: BoardBackground.grid, format: BoardFormat.continuous);
  return t;
}

/// The column of a physics lesson.
void _column(BoardController t) {
  final ink = boardInkColors(BoardBackground.grid);
  t.setColor(ink[0].toARGB32());
  _text(t, _w(0.06, 0.05), _tr('قانون نيوتن الثاني', "Newton's second law"), font: 3);
  _text(t, _w(0.06, 0.2), _tr('القوة المحصّلة = الكتلة × التسارع', 'Net force = mass × acceleration'));
  t.setColor(ink[1].toARGB32());
  _text(t, _w(0.06, 0.36), 'F = m · a', font: 3, width: 0.6);
  t.setColor(ink[4].toARGB32());
  _ink(t, [for (var i = 0; i <= 24; i++) _w(0.06 + i * 0.016, 0.52 + math.sin(i * 0.6) * 0.004)], highlighter: true);
  t.setColor(ink[0].toARGB32());
  _shape(t, BoardShapeKind.rect, _w(0.12, 0.72), _w(0.42, 0.98));
  _text(t, _w(0.2, 0.8), 'm', font: 2, width: 0.12);
  t.setColor(ink[2].toARGB32());
  t.setThickness(2);
  _shape(t, BoardShapeKind.arrow, _w(0.44, 0.85), _w(0.86, 0.85));
  t.setThickness(1);
  _text(t, _w(0.62, 0.74), 'F', font: 2, width: 0.12);
  t.setColor(ink[0].toARGB32());
}

/// Beside the column: a note on the left, a worked example on the right (a page grown both ways).
void _beside(BoardController t) {
  final ink = boardInkColors(BoardBackground.grid);
  t.setColor(ink[5].toARGB32());
  _text(t, _w(-0.46, 0.1), _tr('تذكير: الوحدة نيوتن (N)', 'Reminder: the unit is the newton (N)'), width: 0.4);
  _shape(t, BoardShapeKind.arrow, _w(-0.1, 0.3), _w(0.04, 0.36));
  t.setColor(ink[1].toARGB32());
  _text(t, _w(1.12, 0.05), _tr('مثال محلول', 'Worked example'), font: 2, width: 0.9);
  t.setColor(ink[0].toARGB32());
  _text(t, _w(1.12, 0.22), 'm = 4 kg ,  a = 3 m/s²', width: 0.9);
  _text(t, _w(1.12, 0.38), 'F = 4 × 3 = 12 N', font: 2, width: 0.9);
  t.setColor(ink[3].toARGB32());
  _shape(t, BoardShapeKind.rect, _w(1.08, 0.34), _w(1.72, 0.52));
  t.setColor(ink[2].toARGB32());
  _ink(t, [for (var i = 0; i <= 30; i++) _w(1.12 + i * 0.03, 0.62 + math.sin(i * 0.5) * 0.01)]);
  t.setColor(ink[0].toARGB32());
  _text(t, _w(1.5, 0.7), _tr('ضاعِف الكتلة ← نصف التسارع', 'Double the mass → half the acceleration'), width: 0.85);
  t.select(null);
}

Widget _drawScene(BuildContext context) {
  final c = _once('draw', () {
    final t = _teacher();
    _column(t);
    t.setTool(BoardTool.pen);
    t.setColor(boardInkColors(BoardBackground.grid)[2].toARGB32());
    t.setThickness(2);
    return t;
  });
  return _room(context, WhiteboardRoomView(controller: c, fallbackRtl: _ar, onStop: () {}, onOptions: () {}, keyboard: false));
}

/// Writes a wavy line to the right edge and holds the pen there (the page scrolls right and grows under it).
Future<void> _drawToRight(WidgetTester t) async {
  final stage = t.getRect(find.byType(WhiteboardStage));
  final from = Offset(stage.left + stage.width * 0.45, stage.top + stage.height * 0.42);
  final to = Offset(stage.right - 8, stage.top + stage.height * 0.46);
  final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 16; i++) {
    await t.pump(const Duration(milliseconds: 16));
    final p = Offset.lerp(from, to, i / 16)!;
    await g.moveTo(p + Offset(0, math.sin(i * 0.9) * 12));
  }
  for (var i = 0; i < 22; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  // Still held.
}

/// A viewer of a page grown both ways, wired to its presenter, who looks at the worked example.
BoardController _viewer() {
  final t = _teacher();
  final v = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 'v', isHost: (i) => i == 'teacher_1');
  _controllers.add(v);
  t.send = (topic, bytes, reliable, {to}) async => v.receive(topic, bytes, sender: 'teacher_1');
  t.sendSnapshot();
  _column(t);
  _beside(t);
  t.flush();
  t.reportViewport(const BoardViewportPos(0, 1.6 / _len, left: 1.02, width: 0.8));
  t.flushViewport();
  return v;
}

Widget _viewerScene(BuildContext context) {
  final v = _once('viewer', _viewer);
  return _room(
      context, WhiteboardRoomView(controller: v, fallbackRtl: _ar, presenterName: _tr('د. منى السيد', 'Dr. Mona El-Sayed'), keyboard: false));
}

/// The viewer drags the page to its left end with one finger (they stop following).
Future<void> _panAway(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  final stage = t.getRect(find.byType(WhiteboardStage));
  final g = await t.startGesture(stage.center, pointer: 91);
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(90, 0));
  }
  await g.up();
  await t.pump();
}

Future<void> _panAwayThenFollow(WidgetTester t) async {
  await _panAway(t);
  await t.tap(find.byKey(const ValueKey('board.follow')));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

var _grabPointer = 400;

/// Lets the follow settle, then long-presses the [key] thumb and drags it by [by] (held).
Future<void> Function(WidgetTester) _grab(String key, Offset by) => (t) async {
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      final g = await t.startGesture(t.getCenter(find.byKey(ValueKey(key))), pointer: _grabPointer++);
      await t.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 8; i++) {
        await g.moveBy(by / 8);
        await t.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      // Still held.
    };

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
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
            matchesGoldenFile('goldens/grow_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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
    DrawInputPrefs.offered = true;
  });

  testWidgets('draw', (t) => _render(t, 'draw', _drawScene, act: _drawToRight));
  testWidgets('viewer', (t) => _render(t, 'viewer', _viewerScene, act: _panAway, themes: const [false, true]));
  testWidgets('follow', (t) => _render(t, 'follow', _viewerScene, act: _panAwayThenFollow));
  testWidgets('rails', (t) => _render(t, 'rails', _viewerScene, act: _settle, themes: const [false, true]));
  testWidgets('vgrab', (t) => _render(t, 'vgrab', _viewerScene, act: _grab('board.rail.thumb', const Offset(0, 160))));
  testWidgets('hgrab', (t) => _render(t, 'hgrab', _viewerScene, act: _grab('board.side_rail.thumb', const Offset(-90, 0))));
}
