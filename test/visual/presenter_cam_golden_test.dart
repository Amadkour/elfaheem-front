// Visual review renders of the presenter's camera over a share (D-094; compared by eye like the other test/visual
// files, NOT a CI suite):
//
//   flutter test test/visual/presenter_cam_golden_test.dart --update-goldens [--plain-name share]
//
// → test/visual/goldens/presenter_cam_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   share       a student's room: the teacher's shared screen on the stage, the teacher's camera in the box
//               (bottom-left, opposite my own self-view at the bottom-right), the bar.
//   bubbles     the same with two classmates' cameras as bubbles and "+3", the box medium.
//   board       the teacher's whiteboard on the stage, the teacher's camera as a circle above the dock, my camera off.
//   no_chrome   the bar hidden (tap the stage): the box keeps the picture, the name pill and the mic only.
//   presenter_off  the teacher's camera off, two classmates' on: bubbles only (never an empty box).
//   collapsed   "Minimize to a name": the pill.
//   options     the options sheet (shape, size, minimize).
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/shared/live/live_presenter_cam.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/presenter_cam_box.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/self_view_pip.dart';
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

/// A stand-in camera frame: a room, a person (head + shoulders); [tone] picks the person.
class _FakeCamera extends StatelessWidget {
  const _FakeCamera({this.tone = 0});
  final int tone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final s = w < h ? w : h;
        final head = s * 0.2;
        const bgs = [
          [Color(0xFF7B6A5C), Color(0xFF4A4250), Color(0xFF2C2A33)],
          [Color(0xFF55707E), Color(0xFF3B4D5C), Color(0xFF232B36)],
          [Color(0xFF6E7A5A), Color(0xFF4B5640), Color(0xFF2A3026)],
        ];
        const shirts = [Color(0xFF2F4A6B), Color(0xFF6B3F4A), Color(0xFF8A6A2E)];
        const skins = [
          [Color(0xFFD9A982), Color(0xFFB98563)],
          [Color(0xFFC99A78), Color(0xFFA77457)],
          [Color(0xFFE2B894), Color(0xFFC28E6A)],
        ];
        final t = tone % 3;
        return Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bgs[t]),
            ),
          ),
          Positioned(
            left: w * 0.08,
            top: h * 0.1,
            width: w * 0.22,
            height: h * 0.34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE8D9B5).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            left: w * 0.5 - s * 0.36,
            width: s * 0.72,
            bottom: -s * 0.1,
            height: s * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: shirts[t],
                borderRadius: BorderRadius.vertical(top: Radius.circular(s * 0.3)),
              ),
            ),
          ),
          Positioned(
            left: w * 0.5 - head * 0.8,
            top: h * 0.5 - s * 0.32,
            width: head * 1.6,
            height: head * 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: skins[t], radius: 0.8),
                borderRadius: const BorderRadius.all(Radius.elliptical(100, 120)),
              ),
            ),
          ),
          Positioned(
            left: w * 0.5 - head * 0.82,
            top: h * 0.5 - s * 0.34,
            width: head * 1.64,
            height: head * 0.7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2B211C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(head)),
              ),
            ),
          ),
        ]);
      });
}

Widget _slide() => Container(
      decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, c) {
        final u = c.maxHeight / 14;
        Widget bar(double w, double h, Color col) => Container(
              width: c.maxWidth * w,
              height: h * u / 10,
              margin: EdgeInsets.only(bottom: u),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6)),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(0.55, 22, const Color(0xFF2B3A67)),
          bar(0.35, 12, const Color(0xFF9AA5C4)),
          SizedBox(height: u),
          bar(0.8, 10, const Color(0xFFD5DAE8)),
          bar(0.72, 10, const Color(0xFFD5DAE8)),
          bar(0.64, 10, const Color(0xFFD5DAE8)),
        ]);
      }),
    );

String get _teacher => _tr('د. منى السيد', 'Dr. Mona Elsayed');

/// The share view as the room draws it: the shared screen fitted in a framed area, the presenter badge (top-start),
/// SCREEN (top-end) and the bottom bar.
Widget _shareStage() => LayoutBuilder(builder: (context, c) {
      Widget chip(Widget child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: LivePalette.shade(0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: LivePalette.glassBorder),
            ),
            child: child,
          );
      final label = TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, fontWeight: FontWeight.w800, color: LivePalette.textHigh);
      return Stack(fit: StackFit.expand, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
          child: Container(
            decoration: BoxDecoration(
              color: LivePalette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LivePalette.accent.withValues(alpha: 0.5), width: 1.5),
            ),
            padding: const EdgeInsets.all(1.5),
            child: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _slide())),
          ),
        ),
        PositionedDirectional(
          top: 20,
          start: 20,
          child: chip(Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.screen_share_rounded, size: 14, color: LivePalette.textHigh),
            const SizedBox(width: 6),
            Text(_tr('$_teacher تعرض الشاشة', '$_teacher is presenting'), style: label),
          ])),
        ),
        PositionedDirectional(
          top: 20,
          end: 20,
          child: chip(Text(_tr('شاشة', 'SCREEN'), style: label.copyWith(color: LivePalette.accent))),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 60,
          child: Center(
            child: chip(Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: LivePalette.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_tr('مشاركة مباشرة', 'Live share'), style: label.copyWith(color: LivePalette.textMid)),
            ])),
          ),
        ),
      ]);
    });

Widget _boardStage() => LayoutBuilder(builder: (context, c) {
      final dock = c.maxWidth >= 980 ? 70.0 : 118.0;
      return Stack(fit: StackFit.expand, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, 56, 10, dock),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFFDFDFB), borderRadius: BorderRadius.circular(14)),
            child: CustomPaint(painter: _InkPainter()),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 12,
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: LivePalette.shade(0.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LivePalette.glassBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.draw_rounded, size: 15, color: LivePalette.textHigh),
                const SizedBox(width: 6),
                Text(_tr('سبورة $_teacher', "$_teacher's whiteboard"),
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w800, color: LivePalette.textHigh)),
              ]),
            ),
          ),
        ),
      ]);
    });

class _InkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF2B3A67)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.12, size.height * 0.3);
    for (var i = 0; i < 6; i++) {
      path.relativeQuadraticBezierTo(size.width * 0.04, -size.height * 0.08, size.width * 0.08, 0);
    }
    canvas.drawPath(path, p);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.55), size.shortestSide * 0.14, p..color = const Color(0xFFD9534F));
    canvas.drawLine(Offset(size.width * 0.15, size.height * 0.7), Offset(size.width * 0.5, size.height * 0.7), p..color = const Color(0xFF3C8D5A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The room's badge column (top-right): (i) + minimize, the session clock.
Widget _badges() {
  Widget chip(IconData icon) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: LivePalette.shade(0.5), shape: BoxShape.circle, border: Border.all(color: LivePalette.glassBorder)),
        child: Icon(icon, size: 15, color: LivePalette.textMid),
      );
  return Column(crossAxisAlignment: CrossAxisAlignment.end, textDirection: TextDirection.ltr, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [chip(Icons.info_outline_rounded), const SizedBox(width: 6), chip(Icons.picture_in_picture_alt_rounded)]),
  ]);
}

Widget _peopleBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LivePalette.shade(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LivePalette.glassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.people_rounded, size: 14, color: LivePalette.textMid),
        const SizedBox(width: 5),
        Text('27', style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w700, color: LivePalette.textMid)),
      ]),
    );

LiveControlAction _a(String key, IconData icon, String label, {bool active = false, int badge = 0, bool off = false}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, active: active, badge: badge, off: off, onTap: () {});

Widget _studentBar({bool camOn = true}) {
  final mic = _a('live_room.mic', Icons.mic_off_rounded, 'lr_unmute'.tr, off: true);
  final cam = camOn
      ? _a('live_room.camera', Icons.videocam_rounded, 'lr_camera'.tr, active: true)
      : _a('live_room.camera', Icons.videocam_off_rounded, 'lr_camera'.tr, off: true);
  final hand = _a('live_room.hand', Icons.back_hand_outlined, 'lr_hands'.tr);
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 2);
  return LiveControlBar(
    primary: [mic, cam, hand, react, chat],
    groups: [
      [mic, cam],
      [hand, react, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
  );
}

PresenterCamItem _teacherCam() =>
    PresenterCamItem(id: 't', name: _teacher, video: const _FakeCamera(), speaking: true);

List<PresenterCamItem> _classmates() => [
      PresenterCamItem(id: 's1', name: _tr('سارة أحمد', 'Sara Ahmed'), video: const _FakeCamera(tone: 1), micOn: false),
      PresenterCamItem(id: 's2', name: _tr('يوسف خالد', 'Youssef Khaled'), video: const _FakeCamera(tone: 2), handUp: true),
    ];

/// One student's room: [content] on the stage, the badges, the people badge, the teacher's camera over it and my own
/// self-view, with the room's keep-out rules.
class _Room extends StatefulWidget {
  const _Room({
    required this.content,
    this.prefs = const PresenterCamPrefs(),
    this.main = true,
    this.bubbles = const [],
    this.more = 0,
    this.collapsed = false,
    this.chrome = true,
    this.selfCam = true,
    this.extraTop = 0,
    this.extraBottom = 26,
    this.overlay,
  });

  final Widget content;
  final PresenterCamPrefs prefs;
  final bool main;
  final List<PresenterCamItem> bubbles;
  final int more;
  final bool collapsed;
  final bool chrome;
  final bool selfCam;
  final double extraTop;
  final double extraBottom;
  final Widget? overlay;

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> {
  double _badgesH = 0;

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    final top = 12.0 + widget.extraTop;
    final keep = SelfViewKeepOut(
      base: EdgeInsets.fromLTRB(12, top, 12, 58 + widget.extraBottom),
      topRight: _badgesH > 0 ? (14 + _badgesH + 8 - top).clamp(0.0, 999.0) : 0,
    );
    const self = SelfViewPrefs();
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: LivePalette.bg,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(20), child: widget.content),
                Positioned(
                  top: 14,
                  right: 14,
                  child: SelfViewSizeReporter(
                    onSize: (s) {
                      if ((s.height - _badgesH).abs() > 1) setState(() => _badgesH = s.height);
                    },
                    child: _badges(),
                  ),
                ),
                Positioned(bottom: 14 + (widget.extraBottom > 26 ? widget.extraBottom : 0), right: 14, child: _peopleBadge()),
                Positioned.fill(
                  child: PresenterCamLayer(
                    prefs: widget.prefs,
                    keepOut: keep,
                    selfSide: self.side,
                    avoid: widget.selfCam ? (stage) => selfViewRect(stage: stage, prefs: self, keepOut: keep) : null,
                    main: widget.main ? _teacherCam() : null,
                    bubbles: widget.bubbles,
                    more: widget.more,
                    collapsed: widget.collapsed,
                    showChrome: widget.chrome,
                    onTap: () {},
                    onMenu: () {},
                    onCollapse: () {},
                    onExpand: () {},
                    onPin: (_) {},
                    onMore: () {},
                    onMoved: (_, _) {},
                  ),
                ),
                if (widget.selfCam)
                  Positioned.fill(
                    child: SelfViewLayer(
                      prefs: self,
                      keepOut: keep,
                      onMoved: (_, _) {},
                      tile: SelfViewTile(
                        shape: self.shape,
                        name: _tr('أحمد', 'Ahmed'),
                        video: const _FakeCamera(tone: 1),
                        micOn: false,
                        showChrome: widget.chrome,
                        onMenu: () {},
                      ),
                    ),
                  ),
                ?widget.overlay,
              ]),
            ),
            if (widget.chrome) _studentBar(camOn: widget.selfCam),
          ]),
        ),
      ),
    );
  }
}

Widget _optionsOverlay() => Positioned.fill(
      child: ColoredBox(
        color: LivePalette.shade(0.5),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: DecoratedBox(
                decoration: BoxDecoration(color: LivePalette.surfaceHi, border: const Border(top: BorderSide(color: LivePalette.glassBorder))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(color: LivePalette.glassBorder, borderRadius: BorderRadius.circular(3)),
                  ),
                  SelfViewOptions(
                    prefs: const PresenterCamPrefs().asSelfViewPrefs,
                    showAloneSwitch: false,
                    showCircleTip: false,
                    icon: Icons.co_present_rounded,
                    title: 'lr_presenter_cam'.tr,
                    hint: 'lr_presenter_cam_hint'.tr,
                    hideIcon: Icons.close_fullscreen_rounded,
                    hideTitle: 'lr_presenter_cam_collapse'.tr,
                    hideSubtitle: 'lr_presenter_cam_collapse_sub'.tr,
                    onChanged: (_) {},
                    onHide: () {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

final Map<String, Widget Function(BuildContext)> _scenes = {
  'share': (_) => _Room(content: _shareStage()),
  'bubbles': (_) => _Room(
        content: _shareStage(),
        prefs: const PresenterCamPrefs(size: SelfViewSize.medium),
        bubbles: _classmates(),
        more: 3,
      ),
  'board': (context) => _Room(
        content: _boardStage(),
        prefs: const PresenterCamPrefs(shape: SelfViewShape.circle, size: SelfViewSize.medium),
        selfCam: false,
        extraTop: 52,
        extraBottom: MediaQuery.sizeOf(context).width >= 980 ? 70 : 118,
      ),
  'no_chrome': (_) => _Room(content: _shareStage(), chrome: false, bubbles: _classmates()),
  'presenter_off': (_) => _Room(content: _shareStage(), main: false, bubbles: _classmates(), more: 1),
  'collapsed': (_) => _Room(content: _shareStage(), collapsed: true, bubbles: _classmates(), more: 3),
  'options': (_) => _Room(content: _shareStage(), overlay: _optionsOverlay()),
};

Future<void> _render(WidgetTester tester, String name) async {
  final scene = _scenes[name]!;
  final prevLang = AppConfig.lang;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(scene, dark: dark));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/presenter_cam_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
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

  for (final name in _scenes.keys) {
    testWidgets(name, (t) => _render(t, name));
  }
}
