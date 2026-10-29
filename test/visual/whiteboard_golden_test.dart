// Visual review renders of the live whiteboard (D-087; compared by eye, like the other test/visual files; NOT a CI
// suite):
//
//   flutter test test/visual/whiteboard_golden_test.dart --update-goldens
//
// → test/visual/goldens/whiteboard_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   presenter  the teacher presents a grid board: a graph with axes and a parabola, a circled formula, Arabic and
//              English text boxes, a selected text box (frame, width handle, Edit / Delete), the dock and the bar.
//   typing     the blackboard, the text tool typing into a box (Arabic, right to left), the font sizes on the dock.
//   viewer     a student watching page 2 of 3 of a lined board ("Dr. Mona's whiteboard"), no tools.
//   sheet      the share sheet's Whiteboard tab (background picker) and the Board options sheet.
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart' show WhiteboardStage;
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/share_presets.dart';
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _host(Widget Function(BuildContext) scene, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: Builder(builder: scene)),
    ),
  );
}

// ── A board with content ──────────────────────────────────────────────────────

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

String _text(BoardController c, Offset at, String text, {int font = 1, double width = 0.32}) {
  c.setFontStep(font);
  final id = c.createText(at.dx, at.dy, boxWidth: width)!;
  c.updateText(id, text: text);
  c.endEdit(id);
  return id;
}

/// The physics lesson: axes, a parabola, a circled formula, a heading and a note. Returns the note's id.
String _lesson(BoardController c) {
  final ar = AppConfig.lang == 'ar';
  final colors = boardInkColors(c.background);
  c.setColor(colors[0].toARGB32());
  c.setThickness(1);
  // axes
  _shape(c, BoardShapeKind.arrow, const Offset(0.08, 0.86), const Offset(0.5, 0.86));
  _shape(c, BoardShapeKind.arrow, const Offset(0.08, 0.86), const Offset(0.08, 0.3));
  // the parabola (handwritten: a little wobble)
  c.setColor(colors[1].toARGB32());
  c.setThickness(2);
  _ink(c, [
    for (var i = 0; i <= 60; i++)
      Offset(0.1 + i * 0.0062, 0.84 - (1 - math.pow((i - 30) / 30, 2)) * 0.46 + math.sin(i * 0.9) * 0.002),
  ]);
  // the top of the curve
  c.setColor(colors[2].toARGB32());
  c.setThickness(1);
  _shape(c, BoardShapeKind.ellipse, const Offset(0.255, 0.33), const Offset(0.315, 0.43));
  // heading + formula
  c.setColor(colors[0].toARGB32());
  _text(c, const Offset(0.56, 0.08), ar ? 'المقذوفات' : 'Projectile motion', font: 3, width: 0.4);
  c.setColor(colors[1].toARGB32());
  _text(c, const Offset(0.56, 0.3), 'y = v₀t − ½gt²', font: 2, width: 0.38);
  // highlight the formula
  c.setColor(colors[4].toARGB32());
  c.setThickness(1);
  _ink(c, [for (var i = 0; i <= 30; i++) Offset(0.56 + i * 0.0105, 0.345 + math.sin(i * 0.4) * 0.003)], highlighter: true);
  c.setColor(colors[0].toARGB32());
  final note = _text(
      c,
      const Offset(0.56, 0.5),
      ar ? 'أعلى نقطة عندما تكون السرعة الرأسية صفراً' : 'The highest point is where the vertical speed is zero',
      font: 1,
      width: 0.36);
  c.setColor(colors[2].toARGB32());
  _shape(c, BoardShapeKind.arrow, const Offset(0.55, 0.56), const Offset(0.34, 0.4));
  // a rectangle around the result
  c.setColor(colors[3].toARGB32());
  _shape(c, BoardShapeKind.rect, const Offset(0.55, 0.72), const Offset(0.93, 0.88));
  _text(c, const Offset(0.575, 0.755), ar ? 'زمن الوصول للقمة: t = v₀ / g' : 'Time to the top: t = v₀ / g', font: 1, width: 0.34);
  c.flush();
  return note;
}

BoardController _presenter({required BoardBackground bg}) {
  final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 'g', isHost: (id) => id == 'teacher_1');
  c.startPresenting(background: bg);
  return c;
}

LiveControlAction _a(String key, IconData icon, String label, {bool active = false, bool off = false, Color? color, bool pinned = false}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, active: active, off: off, color: color, pinned: pinned, onTap: () {});

Widget _bar() {
  final mic = _a('live_room.mic', Icons.mic_rounded, 'lr_mute'.tr, active: true);
  final cam = _a('live_room.camera', Icons.videocam_rounded, 'lr_camera'.tr, active: true);
  final share = _a('live_room.share', Icons.stop_screen_share_rounded, _tr('إيقاف العرض', 'Stop presenting'), active: true, color: LivePalette.danger);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, pinned: true);
  final hands = _a('live_room.hands', Icons.back_hand_rounded, 'lr_hands'.tr);
  return LiveControlBar(
    primary: [mic, cam, share, hands, chat],
    secondary: const [],
    groups: [
      [mic, cam],
      [share],
      [hands, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
    rec: LiveRecBadge.recording,
  );
}

Widget _room(BuildContext context, Widget stage) {
  LivePalette.sync(context);
  return Theme(
    data: ThemeData.dark(),
    child: Scaffold(
      backgroundColor: LivePalette.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
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
          _bar(),
        ]),
      ),
    ),
  );
}

final _controllers = <BoardController>[];
final _memo = <String, Object>{};

/// One value per pump (the scene builder may run more than once).
T _once<T extends Object>(String key, T Function() create) => _memo.putIfAbsent(key, create) as T;

Widget _presenterScene(BuildContext context) {
  final c = _once('presenter', () {
    final c = _presenter(bg: BoardBackground.grid);
    _controllers.add(c);
    final note = _lesson(c);
    c.setTool(BoardTool.select);
    c.select(note);
    return c;
  });
  return _room(context, WhiteboardRoomView(controller: c, fallbackRtl: AppConfig.lang == 'ar', onStop: () {}, onOptions: () {}, keyboard: false));
}

Widget _typingScene(BuildContext context) {
  final c = _once('typing', () {
    final c = _presenter(bg: BoardBackground.blackboard);
    _controllers.add(c);
    _lesson(c);
    c.setTool(BoardTool.text);
    c.select(null);
    c.setFontStep(2);
    return c;
  });
  return _room(context, WhiteboardRoomView(controller: c, fallbackRtl: AppConfig.lang == 'ar', onStop: () {}, onOptions: () {}, keyboard: false));
}

Widget _viewerScene(BuildContext context) {
  final student = _once('viewer', () {
    final teacher = _presenter(bg: BoardBackground.lined);
    final student = BoardController(localIdentity: 'student_2', autoFlush: false, isHost: (id) => id == 'teacher_1');
    teacher.send = (topic, bytes, reliable, {to}) async => student.receive(topic, bytes, sender: 'teacher_1');
    _controllers.addAll([teacher, student]);
    teacher.sendSnapshot();
    teacher.addPage();
    _lesson(teacher);
    teacher.addPage();
    teacher.previousPage();
    return student;
  });
  return _room(
    context,
    WhiteboardRoomView(controller: student, presenterName: _tr('د. منى السيد', 'Dr. Mona Elsayed'), fallbackRtl: AppConfig.lang == 'ar', keyboard: false),
  );
}

Widget _sheetScene(BuildContext context) {
  final c = context.colors;
  final narrow = MediaQuery.sizeOf(context).width < 700;
  Widget sheet(Widget child) => Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: c.cardShadow,
        ),
        child: child,
      );
  final share = sheet(ShareOptionsLayout(
    quality: ShareQuality.detail,
    deviceAudio: true,
    deviceAudioSupported: true,
    whiteboard: true,
    tab: ShareTab.whiteboard,
    background: BoardBackground.grid,
    onTab: (_) {},
    onBackground: (_) {},
    onStartWhiteboard: () {},
  ));
  final options = sheet(const WhiteboardOptionsLayout(
    background: BoardBackground.blackboard,
    pageIndex: 1,
    pageCount: 3,
    isHost: true,
    allowStudents: true,
  ));
  return Scaffold(
    backgroundColor: c.background,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: narrow
            ? Column(children: [share, const SizedBox(height: 16), options])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: share),
                const SizedBox(width: 16),
                Expanded(child: options),
              ]),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(BuildContext) scene,
    {Future<void> Function(WidgetTester t)? act}) async {
  final prevLang = AppConfig.lang;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
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
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/whiteboard_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

/// Taps the empty top-left part of the page with the text tool and types into the new box.
Future<void> _typeNewBox(WidgetTester t) async {
  final page = t.getRect(find.byType(WhiteboardStage));
  final rtl = AppConfig.lang == 'ar';
  // An empty spot above the parabola (RTL: the box opens to the left of the tap, so the tap is further right).
  final at = Offset(page.left + page.width * (rtl ? 0.5 : 0.16), page.top + page.height * 0.14);
  await t.tapAt(at);
  await t.pump();
  await t.pump();
  await t.enterText(find.byKey(const ValueKey('board.editor.field')), rtl ? 'السرعة الابتدائية v₀' : 'Initial speed v₀');
  await t.pump();
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('presenter', (t) => _render(t, 'presenter', _presenterScene));
  testWidgets('typing', (t) => _render(t, 'typing', _typingScene, act: _typeNewBox));
  testWidgets('viewer', (t) => _render(t, 'viewer', _viewerScene));
  testWidgets('sheet', (t) => _render(t, 'sheet', _sheetScene));
}
