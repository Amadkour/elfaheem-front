// Visual review renders of D-093 (name tags while people draw, page formats; compared by eye, NOT a CI suite):
//
//   flutter test test/visual/whiteboard_formats_golden_test.dart --update-goldens
//
// → test/visual/goldens/draw_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   tags        the teacher's landscape board while two students draw and a third types: their name tags follow
//               their pens; the mouse over a stroke shows "Drawn by …" (the host's Show who drew what).
//   portrait    a portrait (3:4) board presented from a phone: it fills the width; a student circles the formula.
//   continuous  a student watching a continuous board, scrolled away from the presenter: the rail (where they are,
//               where the presenter is), "Follow Dr. Mona", a classmate's tag.
//   annot       name tags and "Drawn by …" over a shared screen's annotation.
//   share       the share sheet's Whiteboard tab: Page (Landscape · Portrait · Continuous) and the background.
//   board       the Board sheet of a continuous board: page format, save the part on screen / the whole board,
//               students may draw, Show who drew what, Stylus only.
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
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_layer.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_stage.dart' show WhiteboardStage;
import 'package:flutter_education_app/features/live/room/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';
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
final _fixed = DateTime(2026, 10, 29, 10, 30);
DateTime _now() => _fixed;

Widget _host(Widget Function(BuildContext) scene, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: _ar ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: Builder(builder: scene)),
    ),
  );
}

LiveControlAction _a(String key, IconData icon, String label, {bool active = false, Color? color, bool pinned = false}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, active: active, color: color, pinned: pinned, onTap: () {});

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

// ── A tiny room of board controllers ──────────────────────────────────────────

final _names = <String, String>{};
String _nameOf(String id) => _names[id] ?? '';
final _drawers = <String>{};
final _controllers = <ChangeNotifier>[];
final _memo = <String, Object>{};
T _once<T extends Object>(String key, T Function() create) => _memo.putIfAbsent(key, create) as T;

void _setNames() {
  _names
    ..clear()
    ..addAll({
      'teacher_1': _tr('د. منى السيد', 'Dr. Mona Elsayed'),
      'student_2': _tr('عمر خالد', 'Omar Khaled'),
      'student_3': _tr('سارة أحمد', 'Sara Ahmed'),
      'student_4': 'Liam O’Connor',
      'guest_5': _tr('ضيف: نورا', 'Nora (guest)'),
    });
}

List<BoardController> _boardRoom(List<String> ids) {
  final all = <BoardController>[];
  for (final id in ids) {
    final c = BoardController(
      localIdentity: id,
      autoFlush: false,
      idPrefix: id.substring(0, 1) + id.substring(id.length - 1),
      isHost: (i) => i == 'teacher_1',
      studentMayDraw: _drawers.contains,
      nameOf: _nameOf,
      othersMayDraw: () => _drawers.isNotEmpty,
      showAuthors: () => true,
      now: _now,
    );
    c.send = (topic, bytes, reliable, {to}) async {
      for (final o in all) {
        if (o.localIdentity != id && (to == null || to.contains(o.localIdentity))) o.receive(topic, bytes, sender: id);
      }
    };
    all.add(c);
  }
  _controllers.addAll(all);
  return all;
}

void _ink(BoardController c, List<Offset> pts, {bool highlighter = false, bool end = true}) {
  c.beginInk(pts.first.dx, pts.first.dy, highlighter: highlighter);
  for (final p in pts.skip(1)) {
    c.moveInk(p.dx, p.dy);
  }
  c.flush();
  if (end) c.endInk();
}

void _shape(BoardController c, BoardShapeKind k, Offset a, Offset b) {
  c.beginShape(k, a.dx, a.dy);
  c.moveShape(b.dx, b.dy);
  c.endShape();
}

String _text(BoardController c, Offset at, String text, {int font = 1, double width = 0.32, bool end = true}) {
  c.setFontStep(font);
  final id = c.createText(at.dx, at.dy, boxWidth: width)!;
  c.updateText(id, text: text);
  c.flush();
  if (end) {
    c.endEdit(id);
    c.select(null); // the next colour is for the next item, not a restyle of this one
  }
  return id;
}

/// Tags stand where the pens are (the glide would get there within a frame or two on a device).
void _settle(BoardController c) {
  for (final m in c.presence.marks) {
    m
      ..shownX = m.x
      ..shownY = m.y;
  }
}

List<Offset> _loop(Offset c, double rx, double ry, {double turns = 1.05, int n = 48, double wobble = 0.004}) => [
      for (var i = 0; i <= n; i++)
        Offset(
          c.dx + math.cos(-math.pi / 2 + i / n * turns * 2 * math.pi) * rx * (1 + math.sin(i * 0.7) * wobble * 10),
          c.dy + math.sin(-math.pi / 2 + i / n * turns * 2 * math.pi) * ry * (1 + math.cos(i * 0.5) * wobble * 10),
        ),
    ];

// ── Scenes ────────────────────────────────────────────────────────────────────

/// Landscape: the teacher presents; Omar circles, Sara draws an arrow, Liam types; the mouse is over Omar's ring.
Widget _tagsScene(BuildContext context) {
  final teacher = _once('tags', () {
    _drawers.addAll(['student_2', 'student_3', 'student_4']);
    final [t, omar, sara, liam] = _boardRoom(['teacher_1', 'student_2', 'student_3', 'student_4']);
    t.startPresenting(background: BoardBackground.grid);
    final ink = boardInkColors(BoardBackground.grid);
    t.setColor(ink[0].toARGB32());
    _text(t, const Offset(0.06, 0.07), _tr('المعادلات التربيعية', 'Quadratic equations'), font: 3, width: 0.5);
    _text(t, const Offset(0.06, 0.26), 'x² − 5x + 6 = 0', font: 2, width: 0.4);
    t.setColor(ink[1].toARGB32());
    _text(t, const Offset(0.06, 0.42), '(x − 2)(x − 3) = 0', font: 2, width: 0.4);
    t.setColor(ink[0].toARGB32());
    _shape(t, BoardShapeKind.arrow, const Offset(0.56, 0.86), const Offset(0.95, 0.86));
    _shape(t, BoardShapeKind.arrow, const Offset(0.6, 0.92), const Offset(0.6, 0.18));
    t.setColor(ink[1].toARGB32());
    t.setThickness(2);
    _ink(t, [for (var i = 0; i <= 50; i++) Offset(0.64 + i * 0.006, 0.3 + math.pow((i - 25) / 25, 2) * 0.5)]);
    t.setThickness(1);
    // Omar circles the roots (still drawing).
    omar.setColor(ink[2].toARGB32());
    _ink(omar, _loop(const Offset(0.29, 0.475), 0.15, 0.085), end: false);
    // Sara: an arrow toward the vertex.
    sara.setColor(ink[3].toARGB32());
    sara.beginShape(BoardShapeKind.arrow, 0.86, 0.22);
    sara.moveShape(0.8, 0.68);
    sara.flush();
    // Liam types under the formula.
    liam.setColor(ink[5].toARGB32());
    _text(liam, const Offset(0.06, 0.62), 'x = 2  or  x = 3', font: 1, width: 0.3, end: false);
    t.setTool(BoardTool.select); // "Drawn by" shows on hover with the select tool
    t.select(null);
    _settle(t);
    return t;
  });
  return _room(context, WhiteboardRoomView(controller: teacher, fallbackRtl: _ar, onStop: () {}, onOptions: () {}, keyboard: false));
}

/// Portrait, presented from a phone: a student circles the formula.
Widget _portraitScene(BuildContext context) {
  final teacher = _once('portrait', () {
    _drawers.add('student_2');
    final [t, omar] = _boardRoom(['teacher_1', 'student_2']);
    t.startPresenting(background: BoardBackground.lined, format: BoardFormat.portrait);
    final ink = boardInkColors(BoardBackground.lined);
    t.setColor(ink[0].toARGB32());
    _text(t, const Offset(0.07, 0.05), _tr('قانون نيوتن الثاني', "Newton's second law"), font: 3, width: 0.86);
    t.setColor(ink[1].toARGB32());
    _text(t, const Offset(0.3, 0.17), 'F = m · a', font: 3, width: 0.5);
    t.setColor(ink[0].toARGB32());
    // A block on a floor and the forces on it.
    _shape(t, BoardShapeKind.line, const Offset(0.1, 0.62), const Offset(0.9, 0.62));
    _shape(t, BoardShapeKind.rect, const Offset(0.36, 0.45), const Offset(0.62, 0.62));
    t.setColor(ink[2].toARGB32());
    _shape(t, BoardShapeKind.arrow, const Offset(0.62, 0.535), const Offset(0.88, 0.535));
    _text(t, const Offset(0.7, 0.47), 'F', font: 2, width: 0.12);
    t.setColor(ink[3].toARGB32());
    _shape(t, BoardShapeKind.arrow, const Offset(0.49, 0.62), const Offset(0.49, 0.76));
    _text(t, const Offset(0.52, 0.7), 'mg', font: 2, width: 0.16);
    t.setColor(ink[0].toARGB32());
    _text(t, const Offset(0.07, 0.82), _tr('كلما زادت الكتلة قلّ التسارع لنفس القوة', 'The larger the mass, the smaller the acceleration for the same force'),
        font: 1, width: 0.86);
    omar.setColor(ink[2].toARGB32());
    _ink(omar, _loop(const Offset(0.5, 0.215), 0.24, 0.06), end: false);
    t.setTool(BoardTool.pen);
    t.select(null);
    _settle(t);
    return t;
  });
  return _room(context, WhiteboardRoomView(controller: teacher, fallbackRtl: _ar, onStop: () {}, onOptions: () {}, keyboard: false));
}

const _len = kBoardContinuousLength;
Offset _w(double x, double yW) => Offset(x, yW / _len);

/// Continuous: Sara watches; she scrolled away from the presenter (the act below); Omar draws where she looks.
Widget _continuousScene(BuildContext context) {
  final viewer = _once('continuous', () {
    _drawers.add('student_2');
    final [t, omar, sara] = _boardRoom(['teacher_1', 'student_2', 'student_3']);
    t.startPresenting(background: BoardBackground.white, format: BoardFormat.continuous);
    final ink = boardInkColors(BoardBackground.white);
    t.setColor(ink[0].toARGB32());
    _text(t, _w(0.07, 0.06), _tr('الفصل الثالث · المشتقات', 'Chapter 3 · Derivatives'), font: 3, width: 0.86);
    _text(t, _w(0.07, 0.2), _tr('المشتقة تقيس سرعة تغيّر الدالة عند كل نقطة.', 'The derivative measures how fast a function changes at each point.'),
        font: 1, width: 0.86);
    t.setColor(ink[1].toARGB32());
    _text(t, _w(0.07, 0.38), "f'(x) = lim (f(x+h) − f(x)) / h", font: 2, width: 0.86);
    t.setColor(ink[4].toARGB32());
    _ink(t, [for (var i = 0; i <= 30; i++) _w(0.07 + i * 0.026, 0.43 + math.sin(i * 0.5) * 0.004)], highlighter: true);
    // A graph.
    t.setColor(ink[0].toARGB32());
    _shape(t, BoardShapeKind.arrow, _w(0.1, 1.15), _w(0.9, 1.15));
    _shape(t, BoardShapeKind.arrow, _w(0.15, 1.2), _w(0.15, 0.6));
    t.setColor(ink[1].toARGB32());
    t.setThickness(2);
    _ink(t, [for (var i = 0; i <= 50; i++) _w(0.18 + i * 0.014, 1.1 - math.pow(i / 50, 2) * 0.42)]);
    t.setThickness(1);
    t.setColor(ink[2].toARGB32());
    _shape(t, BoardShapeKind.line, _w(0.42, 1.08), _w(0.86, 0.72));
    _text(t, _w(0.6, 0.66), _tr('المماس', 'tangent'), font: 1, width: 0.3);
    t.setColor(ink[0].toARGB32());
    _text(t, _w(0.07, 1.36), _tr('مثال ١', 'Example 1'), font: 2, width: 0.6);
    _text(t, _w(0.07, 1.5), 'f(x) = x³ − 2x', font: 2, width: 0.6);
    _text(t, _w(0.07, 1.66), "f'(x) = 3x² − 2", font: 2, width: 0.6);
    t.setColor(ink[3].toARGB32());
    _shape(t, BoardShapeKind.rect, _w(0.05, 1.63), _w(0.62, 1.77));
    t.setColor(ink[0].toARGB32());
    _text(t, _w(0.07, 2.0), _tr('مثال ٢', 'Example 2'), font: 2, width: 0.6);
    _text(t, _w(0.07, 2.14), 'g(x) = sin(2x)', font: 2, width: 0.6);
    // Omar works on example 1 (open stroke: his tag stays).
    omar.setColor(ink[5].toARGB32());
    _ink(omar, [for (var i = 0; i <= 26; i++) _w(0.66 + i * 0.009, 1.7 + math.sin(i * 0.6) * 0.012)], end: false);
    // The presenter's view: further down, at example 2.
    t.reportViewport(const BoardViewportPos(1.95 / _len, 0.55 / _len));
    sara.presence.remove('teacher_1'); // her last line was minutes ago in the class (the fixed clock keeps it)
    _settle(sara);
    return sara;
  });
  return _room(
    context,
    WhiteboardRoomView(controller: viewer, presenterName: _names['teacher_1']!, fallbackRtl: _ar, keyboard: false),
  );
}

/// The viewer scrolls up, away from the presenter: "Follow …" appears.
Future<void> _scrollAway(WidgetTester t) async {
  final stage = t.getRect(find.byType(WhiteboardStage));
  final narrow = stage.width < 600;
  await t.dragFrom(stage.center, Offset(0, narrow ? 260 : 520));
  await t.pump();
}

/// A shared slide with annotation: the presenter's view; Omar and a guest draw; the mouse is over Sara's line.
Widget _annotScene(BuildContext context) {
  final host = _once('annot', () {
    _setNames();
    final ids = ['teacher_1', 'student_2', 'student_3', 'guest_5'];
    final all = <AnnotationController>[];
    for (final id in ids) {
      final c = AnnotationController(localIdentity: id, autoFlush: false, nameOf: _nameOf, now: _now, idPrefix: id.substring(0, 2));
      c.send = (topic, bytes, reliable, {to}) async {
        for (final o in all) {
          if (o.localIdentity != id) o.receive(topic, bytes, sender: id);
        }
      };
      all.add(c);
    }
    _controllers.addAll(all);
    for (final c in all) {
      c.setRoles(hosts: {'teacher_1'}, presenter: 'teacher_1');
    }
    final [h, omar, sara, nora] = all;
    h.setAllowStudents(true);
    h.setShowAuthors(true);
    void stroke(AnnotationController c, int color, List<Offset> pts, {bool end = true}) {
      c.setColor(color);
      c.begin(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        c.move(p.dx, p.dy);
      }
      c.flush();
      if (end) c.end();
    }

    stroke(sara, 0xFF16A34A, [for (var i = 0; i <= 20; i++) Offset(0.1 + i * 0.016, 0.47 + math.sin(i * 0.5) * 0.004)]);
    stroke(omar, 0xFFDC2626, _loop(const Offset(0.73, 0.55), 0.13, 0.2), end: false);
    stroke(nora, 0xFF7C3AED, [for (var i = 0; i <= 18; i++) Offset(0.2 + i * 0.012, 0.75 - i * 0.004)], end: false);
    for (final m in h.presence.marks) {
      m
        ..shownX = m.x
        ..shownY = m.y;
    }
    return h;
  });
  return _room(
    context,
    Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              const _Slide(),
              AnnotationLayer(controller: host, contentSize: const Size(1920, 1080)),
            ]),
          ),
        ),
      ),
    ),
  );
}

TestGesture? _mouse;
bool _mouseAdded = false;

/// A mouse over the green line (annot) / Omar's ring (tags). One mouse for every render of a scene.
Future<void> Function(WidgetTester) _hoverAt(Offset Function(Rect area) where, Finder area) => (t) async {
      final r = t.getRect(area);
      final g = _mouse ??= await t.createGesture(kind: PointerDeviceKind.mouse);
      if (!_mouseAdded) {
        _mouseAdded = true;
        await g.addPointer(location: r.topLeft + const Offset(1, 1));
      }
      await g.moveTo(r.topLeft + const Offset(2, 2));
      await g.moveTo(where(r));
      await t.pump();
      // The pointer stays (removing it would be a mouse leaving the board: the chip goes).
    };

class _Slide extends StatelessWidget {
  const _Slide();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        TextStyle s(double f, {FontWeight fw = FontWeight.w600, Color col = const Color(0xFF1E293B)}) =>
            TextStyle(fontFamily: AppFonts.family, fontSize: w * f, fontWeight: fw, color: col, height: 1.3);
        return Container(
          color: const Color(0xFFF8FAFC),
          padding: EdgeInsets.fromLTRB(w * 0.07, w * 0.05, w * 0.07, w * 0.04),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tr('الطاقة الحركية', 'Kinetic energy'), style: s(0.045, fw: FontWeight.w800)),
            SizedBox(height: w * 0.02),
            Text('KE = ½ m v²', style: s(0.035, col: const Color(0xFF2563EB))),
            SizedBox(height: w * 0.03),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_tr('• تتضاعف أربع مرات عند مضاعفة السرعة', '• Four times as much at twice the speed'), style: s(0.022, fw: FontWeight.w500)),
                    Text(_tr('• تقاس بالجول', '• Measured in joules'), style: s(0.022, fw: FontWeight.w500)),
                  ]),
                ),
                for (final (i, h) in [0.2, 0.35, 0.55, 0.8].indexed)
                  Container(
                    width: w * 0.05,
                    height: w * 0.25 * h,
                    margin: EdgeInsetsDirectional.only(start: w * 0.02),
                    decoration: BoxDecoration(
                      color: Color.lerp(const Color(0xFF93C5FD), const Color(0xFF1D4ED8), i / 3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
            ),
          ]),
        );
      });
}

Widget _sheet(BuildContext context, Widget child) {
  final c = context.colors;
  return Scaffold(
    backgroundColor: c.background,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: c.cardShadow,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _shareScene(BuildContext context) => _sheet(
      context,
      ShareOptionsLayout(
        quality: ShareQuality.detail,
        deviceAudio: true,
        deviceAudioSupported: true,
        whiteboard: true,
        tab: ShareTab.whiteboard,
        background: BoardBackground.white,
        boardFormat: BoardFormat.portrait,
        onTab: (_) {},
        onBackground: (_) {},
        onBoardFormat: (_) {},
        onStartWhiteboard: () {},
      ),
    );

Widget _boardScene(BuildContext context) => _sheet(
      context,
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 16),
        WhiteboardOptionsLayout(
          background: BoardBackground.grid,
          format: BoardFormat.continuous,
          pageIndex: 0,
          pageCount: 2,
          isHost: true,
          allowStudents: true,
          showAuthors: true,
          stylusOnly: true,
          onFormat: (_) {},
          onBackground: (_) {},
          onAllowStudents: (_) {},
          onShowAuthors: (_) {},
          onStylusOnly: (_) {},
          onExport: () {},
          onExportWhole: () {},
          onClearPage: () {},
        ),
      ]),
    );

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
          _drawers.clear();
          _setNames();
          await tester.pumpWidget(_host(scene, dark: dark));
          await tester.pump(const Duration(milliseconds: 100));
          if (act != null) await act(tester);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/draw_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    if (_mouseAdded) await _mouse?.removePointer();
    _mouse = null;
    _mouseAdded = false;
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
  setUp(() => AppConfig.disableList = []);

  testWidgets('tags', (t) => _render(t, 'tags', _tagsScene, act: (t) async {
        // The mouse over Omar's ring.
        final stage = t.getRect(find.byType(WhiteboardStage));
        final page = boardFitPage(stage.size, kBoardAspect);
        final at = stage.topLeft + page.topLeft + Offset(page.width * 0.29, page.height * (0.475 + 0.085));
        await _hoverAt((_) => at, find.byType(WhiteboardStage))(t);
      }));
  testWidgets('portrait', (t) => _render(t, 'portrait', _portraitScene));
  testWidgets('continuous', (t) => _render(t, 'continuous', _continuousScene, act: _scrollAway));
  testWidgets('annot', (t) => _render(t, 'annot', _annotScene,
      act: _hoverAt((r) => r.topLeft + Offset(r.width * 0.26, r.height * 0.47), find.byType(AnnotationLayer))));
  testWidgets('share', (t) => _render(t, 'share', _shareScene));
  testWidgets('board', (t) => _render(t, 'board', _boardScene));
  testWidgets('board_end', (t) => _render(t, 'board_end', _boardScene, act: (t) async {
        await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
        await t.pump();
      }));
}
