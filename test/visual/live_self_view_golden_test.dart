// Visual review renders of the live room's self-view (D-092; compared by eye like the other test/visual files, NOT a
// CI suite):
//
//   flutter test test/visual/live_self_view_golden_test.dart --update-goldens [--plain-name box_alone]
//
// → test/visual/goldens/live_self_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   box_alone       the teacher alone with the camera on: the waiting card on the stage, my camera in the box
//                   (bottom-right, below the badge column), the bar.
//   circle_remote   a student's camera on the stage, my camera as a circle top-left.
//   share           my shared screen on the stage, my camera in a medium box.
//   board           a whiteboard on the stage, my camera as a circle above the dock.
//   no_chrome       the bar hidden (tap the stage): the box keeps only the picture and the muted mic.
//   hidden          "Hide self view": only the chip that brings it back.
//   alone_stage     "Fill the screen while I'm alone": my camera on the stage, the chip back to a box.
//   options         the self-view options sheet over the room.
//   prejoin_circle  the pre-join page with the camera as a circle and the shape switch.
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
import 'package:flutter_education_app/features/live/live_self_view.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant.dart' show ParticipantTileLayout;
import 'package:flutter_education_app/features/live/room/widgets/recording_placeholder.dart';
import 'package:flutter_education_app/features/live/room/widgets/self_view_pip.dart';
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

/// A stand-in camera frame: a room, a person (head + shoulders). [warm] = me (the teacher), else a student.
class _FakeCamera extends StatelessWidget {
  const _FakeCamera({this.warm = true});
  final bool warm;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final s = w < h ? w : h;
        final head = s * 0.2;
        final bg = warm
            ? const [Color(0xFF7B6A5C), Color(0xFF4A4250), Color(0xFF2C2A33)]
            : const [Color(0xFF55707E), Color(0xFF3B4D5C), Color(0xFF232B36)];
        return Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
            ),
          ),
          // a window / shelf behind
          Positioned(
            left: w * 0.08,
            top: h * 0.1,
            width: w * 0.22,
            height: h * 0.34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (warm ? const Color(0xFFE8D9B5) : const Color(0xFFB9D3E0)).withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // shoulders
          Positioned(
            left: w * 0.5 - s * 0.36,
            width: s * 0.72,
            bottom: -s * 0.1,
            height: s * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: warm ? const Color(0xFF2F4A6B) : const Color(0xFF6B3F4A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(s * 0.3)),
              ),
            ),
          ),
          // head
          Positioned(
            left: w * 0.5 - head * 0.8,
            top: h * 0.5 - s * 0.32,
            width: head * 1.6,
            height: head * 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: warm ? const [Color(0xFFD9A982), Color(0xFFB98563)] : const [Color(0xFFC99A78), Color(0xFFA77457)],
                  radius: 0.8,
                ),
                borderRadius: const BorderRadius.all(Radius.elliptical(100, 120)),
              ),
            ),
          ),
          // hair
          Positioned(
            left: w * 0.5 - head * 0.82,
            top: h * 0.5 - s * 0.34,
            width: head * 1.64,
            height: head * 0.7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: warm ? const Color(0xFF2B211C) : const Color(0xFF1E1A18),
                borderRadius: BorderRadius.vertical(top: Radius.circular(head)),
              ),
            ),
          ),
        ]);
      });
}

Widget _sharedSlide() => Container(
      decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(19)),
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

/// The room's badge column (top-right): (i) + minimize, the session clock, REC.
Widget _badges() {
  Widget chip(IconData icon) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: LivePalette.shade(0.5), shape: BoxShape.circle, border: Border.all(color: LivePalette.glassBorder)),
        child: Icon(icon, size: 15, color: LivePalette.textMid),
      );
  Widget pill(Widget dot, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.58),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          dot,
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
  return Column(crossAxisAlignment: CrossAxisAlignment.end, textDirection: TextDirection.ltr, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [chip(Icons.info_outline_rounded), const SizedBox(width: 6), chip(Icons.picture_in_picture_alt_rounded)]),
    const SizedBox(height: 6),
    pill(const Icon(Icons.schedule_rounded, size: 12, color: LivePalette.textMid), '24:18', LivePalette.textMid),
    const SizedBox(height: 6),
    pill(Container(width: 7, height: 7, decoration: BoxDecoration(color: LivePalette.danger, shape: BoxShape.circle)), 'REC', LivePalette.danger),
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

LiveControlAction _a(String key, IconData icon, String label, {String? compact, bool active = false, int badge = 0, bool off = false, Color? color}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, compactLabel: compact, active: active, badge: badge, off: off, color: color, onTap: () {});

Widget _teacherBar({bool sharing = false, bool micOn = true}) {
  final mic = micOn ? _a('live_room.mic', Icons.mic_rounded, 'lr_mute'.tr) : _a('live_room.mic', Icons.mic_off_rounded, 'lr_unmute'.tr, off: true);
  final cam = _a('live_room.camera', Icons.videocam_rounded, 'lr_camera'.tr, active: true);
  final share = _a('live_room.share', sharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
      sharing ? 'lr_stop_share'.tr : 'lr_share'.tr, active: sharing, color: sharing ? LivePalette.danger : null);
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 3);
  final hands = _a('live_room.hands', Icons.back_hand_outlined, 'lr_hands'.tr, badge: 1);
  return LiveControlBar(
    primary: [mic, cam, share, react, chat],
    secondary: [hands],
    groups: [
      [mic, cam, share],
      [react, hands, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
  );
}

String get _me => _tr('د. منى السيد', 'Dr. Mona Elsayed');

/// One room screen: [content] on the stage, the badges, the people badge, the self-view as the room places it
/// (the same keep-out rules: 12 around, 58 at the bottom for the badge row, the measured badge column on the right).
class _Room extends StatefulWidget {
  const _Room({
    required this.content,
    this.prefs = const SelfViewPrefs(),
    this.hidden = false,
    this.chrome = true,
    this.micOn = true,
    this.selfOnStage = false,
    this.sharing = false,
    this.extraTop = 0,
    this.extraBottom = 0,
    this.overlay,
  });

  final Widget content;
  final SelfViewPrefs prefs;
  final bool hidden;
  final bool chrome;
  final bool micOn;
  final bool selfOnStage;
  final bool sharing;
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
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: LivePalette.bg,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: widget.selfOnStage ? const _FakeCamera() : widget.content,
                ),
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
                Positioned(bottom: 14 + widget.extraBottom, right: 14, child: _peopleBadge()),
                if (widget.selfOnStage)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: SelfViewChip(icon: Icons.picture_in_picture_alt_rounded, label: 'lr_self_view_to_box'.tr, onTap: () {}),
                  )
                else
                  Positioned.fill(
                    child: SelfViewLayer(
                      prefs: widget.prefs,
                      keepOut: keep,
                      hidden: widget.hidden,
                      onMoved: (_, _) {},
                      tile: SelfViewTile(
                        shape: widget.prefs.shape,
                        name: _me,
                        video: const _FakeCamera(),
                        micOn: widget.micOn,
                        showChrome: widget.chrome,
                        onMenu: () {},
                      ),
                    ),
                  ),
                ?widget.overlay,
              ]),
            ),
            if (widget.chrome) _teacherBar(sharing: widget.sharing, micOn: widget.micOn),
          ]),
        ),
      ),
    );
  }
}

Widget _waiting() => RecordingPlaceholderFrame(
      host: PlaceholderParticipant(name: _me, isHost: true, isSpeaking: true, audioLevel: 0.4),
      sessionTitle: _tr('محاضرة الفيزياء — الأسبوع السابع', 'Physics lecture — week 7'),
      platformName: 'NextBrain',
      live: false,
    );

Widget _studentTile() => LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Padding(
        padding: EdgeInsets.fromLTRB(10, wide ? 40 : 56, 10, wide ? 40 : 56),
        child: Center(
          child: AspectRatio(
            aspectRatio: wide ? 16 / 9 : 3 / 4,
            child: ParticipantTileLayout(
              name: _tr('سارة أحمد', 'Sara Ahmed'),
              isSpeaking: true,
              audioLevel: 0.5,
              camOn: true,
              radius: 18,
              child: const _FakeCamera(warm: false),
            ),
          ),
        ),
      );
    });

Widget _shareStage() => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LivePalette.accent.withValues(alpha: 0.5), width: 1.5),
        ),
        padding: const EdgeInsets.all(1.5),
        child: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _sharedSlide())),
      ),
    );

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
        // the board's dock
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: Container(
              height: 52,
              width: 330,
              decoration: BoxDecoration(
                color: LivePalette.shade(0.6),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: LivePalette.glassBorder),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final i in [Icons.near_me_rounded, Icons.edit_rounded, Icons.brush_rounded, Icons.crop_square_rounded, Icons.text_fields_rounded, Icons.undo_rounded])
                  Icon(i, size: 20, color: LivePalette.textMid),
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
                    prefs: const SelfViewPrefs(shape: SelfViewShape.circle),
                    onChanged: (_) {},
                    onHide: () {},
                    onToStage: () {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

Widget _prejoin(BuildContext context) => Scaffold(
      backgroundColor: context.colors.background,
      body: PreJoinLayout(
        title: _tr('محاضرة الفيزياء — الأسبوع السابع', 'Physics lecture — week 7'),
        subtitle: 'lr_ready_to_join'.tr,
        isTeacher: true,
        userName: _me,
        preview: const _FakeCamera(),
        micOn: true,
        camOn: true,
        onToggleMic: () {},
        onToggleCam: () {},
        mics: const [('m1', 'Default microphone')],
        cams: const [('c1', 'Front camera')],
        selectedMic: 'm1',
        selectedCam: 'c1',
        onMicChanged: (_) {},
        onCamChanged: (_) {},
        busy: false,
        onJoin: () {},
        onBack: () {},
        previewShape: SelfViewShape.circle,
        onPreviewShape: (_) {},
      ),
    );

final Map<String, Widget Function(BuildContext)> _scenes = {
  'box_alone': (_) => _Room(content: _waiting()),
  'circle_remote': (_) => _Room(
        content: _studentTile(),
        prefs: const SelfViewPrefs(shape: SelfViewShape.circle, side: SelfViewSide.left, y: 0),
      ),
  'share': (_) => _Room(
        content: _shareStage(),
        sharing: true,
        prefs: const SelfViewPrefs(size: SelfViewSize.medium, y: 0.55),
        extraBottom: 26,
      ),
  'board': (context) => _Room(
        content: _boardStage(),
        prefs: const SelfViewPrefs(shape: SelfViewShape.circle, size: SelfViewSize.medium),
        extraTop: 52,
        extraBottom: MediaQuery.sizeOf(context).width >= 980 ? 70 : 118,
      ),
  'no_chrome': (_) => _Room(content: _studentTile(), chrome: false, micOn: false),
  'hidden': (_) => _Room(content: _studentTile(), hidden: true),
  'alone_stage': (_) => _Room(content: _waiting(), selfOnStage: true),
  'options': (_) => _Room(content: _studentTile(), overlay: _optionsOverlay()),
  'prejoin_circle': _prejoin,
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
            matchesGoldenFile('goldens/live_self_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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
