// Visual review renders of the live room's top row + bottom bar (D-095), compared by eye like the other
// test/visual files (NOT a CI suite):
//
//   flutter test test/visual/live_top_row_golden_test.dart --update-goldens [--plain-name teacher]
//
// → test/visual/goldens/live_top_row_<scene>_<width>_<lang>.png at 390×844 and 1440×900, Arabic and English.
//   teacher   a course's teacher sharing slides: LIVE time, weak network, REC + time (menu), Full view, Minimize;
//             the bar without any recording button.
//   menu      the same with the recording menu open (a meeting creator: Pause + Stop recording).
//   creator   a meeting creator before recording, on the waiting card (no logo): the free-time countdown with
//             Upgrade and the red Record button.
//   paused    the teacher's recording paused, the room locked, a student's camera on the stage.
//   student   a student watching the whiteboard while the server records: REC without controls; the page number
//             on the same line (D-108).
//   board     the teacher presenting the whiteboard while recording: the board's title, ‹ 2 / 3 › + Page, Board
//             options and Stop on the recording's line — ONE line (D-108); a phone folds the rest into ⋮.
//   boardmore the same on a crowded row with the ⋮ menu open.
//   focus     full view (D-108): only the shared slides and the presenter's camera box — no bars, no self-view.
//   focusbars full view after a tap: the top row (Exit) and the bar slid in over the content.
//   focusboard full view of the whiteboard page after a tap.
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
import 'package:flutter_education_app/features/live/live_presenter_cam.dart' show PresenterCamPrefs;
import 'package:flutter_education_app/features/live/live_self_view.dart';
import 'package:flutter_education_app/features/live/live_share_arbiter.dart';
import 'package:flutter_education_app/features/live/live_time_limit.dart' show LiveLimitTone;
import 'package:flutter_education_app/features/live/room/widgets/controls.dart' show ControlsWidgetState;
import 'package:flutter_education_app/features/live/room/widgets/live_avatar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_focus_chrome.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_top_row.dart';
import 'package:flutter_education_app/features/live/room/widgets/presenter_cam_box.dart';
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
void _noop() {}

Widget _host(Widget Function(BuildContext) scene) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      // The boundary holds the whole navigator, so an open menu is in the picture too.
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(builder: (context) {
        LivePalette.sync(context);
        return Theme(data: ThemeData.dark(), child: Scaffold(backgroundColor: LivePalette.bg, body: scene(context)));
      }),
    ),
  );
}

// ── Stage stand-ins ────────────────────────────────────────────────────────────

Widget _slides() => ColoredBox(
      color: const Color(0xFFF6F7FB),
      // A 640 x 400 slide scaled to the stage (the stand-in never overflows on a phone).
      child: FittedBox(child: Container(width: 640, height: 400, padding: const EdgeInsets.all(28), child: LayoutBuilder(builder: (context, c) {
        Widget bar(double w, double h, Color col) => Container(
              width: c.maxWidth * w,
              height: h,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6)),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(0.55, 22, const Color(0xFF2B3A67)),
          bar(0.35, 12, const Color(0xFF9AA5C4)),
          const SizedBox(height: 12),
          bar(0.8, 10, const Color(0xFFD5DAE8)),
          bar(0.72, 10, const Color(0xFFD5DAE8)),
          bar(0.64, 10, const Color(0xFFD5DAE8)),
          const Spacer(),
          Align(alignment: AlignmentDirectional.bottomEnd, child: bar(0.3, 60, const Color(0xFFE3E8F6))),
        ]);
      }))),
    );

Widget _shareStage() => Container(
      color: const Color(0xFF0E1422),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _slides()),
        ),
      ),
    );

Widget _camera({bool warm = true}) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: warm
              ? const [Color(0xFF7B6A5C), Color(0xFF4A4250), Color(0xFF2C2A33)]
              : const [Color(0xFF55707E), Color(0xFF3B4D5C), Color(0xFF232B36)],
        ),
      ),
      child: Center(child: LiveAvatar(name: _tr('سارة أحمد', 'Sara Ahmed'), size: 110, isSpeaking: true, audioLevel: 0.5)),
    );

Widget _board() => Container(
      color: const Color(0xFF0E1422),
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12)),
        child: CustomPaint(painter: _Ink()),
      ),
    );

class _Ink extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF2B5BD7)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.15, size.height * 0.6);
    for (var i = 1; i <= 8; i++) {
      path.lineTo(size.width * (0.15 + i * 0.08), size.height * (0.6 - (i.isEven ? 0.18 : 0.02) - i * 0.02));
    }
    canvas.drawPath(path, p);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.3), size.shortestSide * 0.1, p..color = const Color(0xFFE5484D));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _waiting() => RecordingPlaceholderFrame(
      host: PlaceholderParticipant(name: _tr('منى السيد', 'Mona Elsayed'), isHost: true, isSpeaking: true, audioLevel: 0.4),
      others: [
        PlaceholderParticipant(name: _tr('سارة أحمد', 'Sara Ahmed')),
        PlaceholderParticipant(name: _tr('عمر خالد', 'Omar Khaled'), micOn: false),
      ],
      sessionTitle: _tr('اجتماع فريق المناهج', 'Curriculum team meeting'),
      platformName: 'NextBrain',
      showLogo: false,
      live: false,
    );

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

// ── Bars ───────────────────────────────────────────────────────────────────────

LiveControlAction _a(String key, IconData icon, String label, {String? compact, bool active = false, int badge = 0, bool pinned = false, bool off = false, Color? color}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, compactLabel: compact, active: active, badge: badge, pinned: pinned, off: off, color: color, onTap: _noop);

Widget _bar({required bool host, bool sharing = false}) {
  final mic = _a('live_room.mic', Icons.mic_rounded, 'lr_mute'.tr, active: true);
  final cam = _a('live_room.camera', Icons.videocam_rounded, 'lr_camera'.tr, active: true);
  final share = ControlsWidgetState.shareAction(sharing ? LiveShareButton.stop : (host ? LiveShareButton.share : LiveShareButton.request), onTap: _noop)!;
  final annotate = sharing ? ControlsWidgetState.annotateAction(onTap: _noop) : null;
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final hand = host
      ? _a('live_room.hands', Icons.back_hand_rounded, 'lr_hands'.tr, active: true, color: LivePalette.warning, badge: 2)
      : _a('live_room.hand', Icons.back_hand_outlined, 'lr_raise_hand'.tr);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 3, pinned: true);
  final speaker = _a('live_room.speaker', Icons.speaker_phone_rounded, 'lr_speaker'.tr, active: true);
  return LiveControlBar(
    primary: [mic, cam, share, ?annotate, react, hand, chat],
    secondary: [speaker],
    groups: [
      [mic, cam, speaker],
      [share, ?annotate],
      [react, hand, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
    onLobby: host ? _noop : null,
    waitingCount: host ? 1 : 0,
  );
}

/// The presenter's camera box over the content (kept in full view: it is part of what is presented).
Widget _presenterCam() => Positioned.fill(
      child: PresenterCamLayer(
        prefs: const PresenterCamPrefs(),
        keepOut: const SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 24)),
        selfSide: SelfViewSide.right,
        onMoved: (_, _) {},
        showChrome: false,
        main: PresenterCamItem(id: 'p', name: _tr('منى السيد', 'Mona Elsayed'), video: _camera(warm: false)),
      ),
    );

/// The room page as room.dart lays it out: the top row, the stage (rounded, with the participant badge; the
/// self-view box), the bar — or, in full view (D-108), the content alone with LiveFocusChrome's bars over it.
Widget _room({required LiveTopRow? row, required Widget stage, Widget? bar, bool focus = false, bool bars = false, bool selfBox = true, bool share = false}) =>
    Builder(builder: (context) {
      if (focus) {
        return Stack(fit: StackFit.expand, children: [
          SafeArea(child: Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: stage), _presenterCam()])),
          LiveFocusChrome(
            shown: bars,
            hint: !bars,
            top: row == null ? null : Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: row),
            bottom: bar,
          ),
        ]);
      }
      return SafeArea(
        child: Column(children: [
          if (row != null) Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: row),
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(borderRadius: BorderRadius.circular(20), child: stage),
              Positioned(bottom: 14, right: 14, child: _peopleBadge()),
              if (selfBox)
                Positioned.fill(
                  child: SelfViewLayer(
                    prefs: const SelfViewPrefs(),
                    // room.dart's _selfKeepOut: 58 over the badge row, 84 over a share, 72 in full view.
                    keepOut: SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, share ? 84 : (focus ? 72 : 58))),
                    onMoved: (_, _) {},
                    tile: SelfViewTile(
                      shape: SelfViewShape.box,
                      name: _tr('منى السيد', 'Mona Elsayed'),
                      video: _camera(warm: false),
                      showChrome: !focus,
                      onMenu: _noop,
                    ),
                  ),
                ),
            ]),
          ),
          if (bar != null && !focus) bar,
        ]),
      );
    });

LiveTopRow _teacherRow({bool stop = false}) => LiveTopRow(
      onInfo: _noop,
      liveFor: const Duration(minutes: 24, seconds: 51),
      netLowered: true,
      recording: LiveTopRecording(
        phase: LiveRecPhase.recording,
        elapsed: const Duration(minutes: 18, seconds: 7),
        detail: _tr('الجزء 36 · 41.2 م.ب', 'Part 36 · 41.2 MB'),
        onPause: _noop,
        onStop: stop ? _noop : null,
      ),
      onFocus: _noop,
      onMinimize: _noop,
    );

Widget _teacherScene(BuildContext context) => _room(row: _teacherRow(), stage: _shareStage(), bar: _bar(host: true, sharing: true), share: true);

Widget _menuScene(BuildContext context) => _room(row: _teacherRow(stop: true), stage: _shareStage(), bar: _bar(host: true, sharing: true), share: true);

Widget _creatorScene(BuildContext context) => _room(
      row: const LiveTopRow(
        onInfo: _noop,
        liveFor: Duration(minutes: 12, seconds: 40),
        limit: LiveTopLimit(remaining: Duration(minutes: 2, seconds: 20), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: _noop),
        recording: LiveTopRecording(phase: LiveRecPhase.offer, onRecord: _noop),
        onMinimize: _noop,
      ),
      stage: _waiting(),
      bar: _bar(host: true),
      selfBox: false,
    );

Widget _pausedScene(BuildContext context) => _room(
      row: const LiveTopRow(
        onInfo: _noop,
        liveFor: Duration(hours: 1, minutes: 5, seconds: 9),
        locked: true,
        onLocked: _noop,
        recording: LiveTopRecording(phase: LiveRecPhase.paused, elapsed: Duration(minutes: 52, seconds: 3), onResume: _noop),
        onFocus: _noop,
        onMinimize: _noop,
      ),
      stage: _camera(),
      bar: _bar(host: true),
    );

Widget _studentScene(BuildContext context) => _room(
      row: LiveTopRow(
        onInfo: _noop,
        liveFor: const Duration(minutes: 33, seconds: 2),
        recording: const LiveTopRecording(phase: LiveRecPhase.server),
        board: LiveTopBoard(presenting: false, pageIndex: 1, pageCount: 3, presenterName: _tr('منى السيد', 'Mona Elsayed'), canDraw: true),
        onFocus: _noop,
        onMinimize: _noop,
      ),
      stage: _board(),
      bar: _bar(host: false),
      selfBox: false,
    );

LiveTopRow _boardRow({bool crowded = false, bool focused = false}) => LiveTopRow(
      onInfo: _noop,
      liveFor: const Duration(minutes: 24, seconds: 51),
      netLowered: crowded,
      locked: crowded,
      onLocked: _noop,
      limit: crowded ? const LiveTopLimit(remaining: Duration(minutes: 2, seconds: 20), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: _noop) : null,
      recording: LiveTopRecording(
        phase: LiveRecPhase.recording,
        elapsed: const Duration(minutes: 18, seconds: 7),
        onPause: _noop,
      ),
      board: const LiveTopBoard(
          presenting: true, pageIndex: 1, pageCount: 3, onPrevious: _noop, onNext: _noop, onAddPage: _noop, onOptions: _noop, onStop: _noop),
      onFocus: _noop,
      focused: focused,
      onMinimize: _noop,
    );

Widget _boardScene(BuildContext context) => _room(row: _boardRow(), stage: _board(), bar: _bar(host: true), selfBox: false);

Widget _boardMoreScene(BuildContext context) => _room(row: _boardRow(crowded: true), stage: _board(), bar: _bar(host: true), selfBox: false);

LiveTopRow _focusRow() => LiveTopRow(
      onInfo: _noop,
      liveFor: const Duration(minutes: 24, seconds: 51),
      recording: LiveTopRecording(phase: LiveRecPhase.recording, elapsed: const Duration(minutes: 18, seconds: 7), onPause: _noop),
      onFocus: _noop,
      focused: true,
      onMinimize: _noop,
    );

Widget _focusScene(BuildContext context) =>
    _room(row: _focusRow(), stage: _shareStage(), bar: _bar(host: true, sharing: true), focus: true, share: true);

Widget _focusBarsScene(BuildContext context) =>
    _room(row: _focusRow(), stage: _shareStage(), bar: _bar(host: true, sharing: true), focus: true, bars: true, share: true);

Widget _focusBoardScene(BuildContext context) =>
    _room(row: _boardRow(focused: true), stage: _board(), bar: _bar(host: true), focus: true, bars: true);

Future<void> _render(WidgetTester tester, String name, Widget Function(BuildContext) scene, {Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false; // real shadows (the test default draws them as solid black outlines)
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(scene));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (act != null) {
          await act(tester);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/live_top_row_${name}_${size.width.toInt()}_$lang.png'));
      }
    }
  } finally {
    debugDisableShadows = true;
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

  testWidgets('teacher', (t) => _render(t, 'teacher', _teacherScene));
  testWidgets('menu', (t) => _render(t, 'menu', _menuScene, act: (t) async {
        await t.tap(find.byKey(const ValueKey('live_room.rec_control')).hitTestable());
        await t.pump();
      }));
  testWidgets('creator', (t) => _render(t, 'creator', _creatorScene));
  testWidgets('paused', (t) => _render(t, 'paused', _pausedScene));
  testWidgets('student', (t) => _render(t, 'student', _studentScene));
  testWidgets('board', (t) => _render(t, 'board', _boardScene));
  testWidgets('boardmore', (t) => _render(t, 'boardmore', _boardMoreScene, act: (t) async {
        final more = find.byKey(const ValueKey('live_room.top_more')).hitTestable();
        if (more.evaluate().isNotEmpty) {
          await t.tap(more);
          await t.pump();
        }
      }));
  testWidgets('focus', (t) => _render(t, 'focus', _focusScene));
  testWidgets('focusbars', (t) => _render(t, 'focusbars', _focusBarsScene));
  testWidgets('focusboard', (t) => _render(t, 'focusboard', _focusBoardScene));
}
