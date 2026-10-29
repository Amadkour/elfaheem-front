// Visual review renders of the live room's share arbitration + attention cues (compared by eye, like the other
// test/visual files; NOT a CI suite):
//
//   flutter test test/visual/live_share_golden_test.dart --update-goldens
//
// → test/visual/goldens/live_share_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   host     the teacher's room: a student's share on the stage with Stop share, a chat preview, the bar with the
//            "More" badge (phone) / the chat + hands badges (desktop), and the request dialog on top.
//   student  a student's room: Ask to share / Waiting… on the bar, the minimized box with its badge.
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
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart';
import 'package:flutter_education_app/features/shared/live/live_share_arbiter.dart';
import 'package:flutter_education_app/features/shared/live/live_share_widgets.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/controls.dart' show ControlsWidgetState;
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_avatar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
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
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) {
          LivePalette.sync(context);
          return Theme(data: ThemeData.dark(), child: Scaffold(backgroundColor: LivePalette.bg, body: scene(context)));
        }),
      ),
    ),
  );
}

// ── Scene parts ────────────────────────────────────────────────────────────────

/// A stand-in for a shared slide deck (the stage's video).
Widget _sharedSlide() => Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(19),
      ),
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(builder: (context, c) {
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
          Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: bar(0.3, 60, const Color(0xFFE3E8F6)),
          ),
        ]);
      }),
    );

Widget _presenterPill(String name) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: LivePalette.shade(0.55),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: LivePalette.glassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_rounded, size: 13, color: LivePalette.textMid),
        const SizedBox(width: 6),
        Text(name, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w700, color: LivePalette.textMid)),
      ]),
    );

Widget _stage({required Widget content, Widget? topStart, Widget? bottomStart}) => Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -0.3), radius: 1.2, colors: [LivePalette.surfaceHi, LivePalette.bg]),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 72), child: content),
          if (topStart != null) PositionedDirectional(top: 20, start: 20, end: 112, child: Align(alignment: AlignmentDirectional.topStart, child: topStart)),
          if (bottomStart != null)
            PositionedDirectional(start: 12, end: 12, bottom: 60, child: Align(alignment: AlignmentDirectional.bottomStart, child: bottomStart)),
        ]),
      ),
    );

LiveControlAction _a(String key, IconData icon, String label, {String? compact, bool active = false, int badge = 0, int? attention, bool pinned = false, Color? color, bool off = false}) =>
    LiveControlAction(
        key: ValueKey(key), icon: icon, label: label, compactLabel: compact, active: active, badge: badge, attention: attention, pinned: pinned, color: color, off: off, onTap: () {});

Widget _hostBar() {
  final mic = _a('live_room.mic', Icons.mic_rounded, 'lr_mute'.tr, active: true);
  final cam = _a('live_room.camera', Icons.videocam_off_rounded, 'lr_cam_off'.tr, compact: 'lr_camera'.tr, off: true);
  final share = ControlsWidgetState.shareAction(LiveShareButton.share, onTap: () {})!;
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final hands = _a('live_room.hands', Icons.back_hand_rounded, 'lr_hands'.tr, active: true, color: LivePalette.warning, badge: 3, attention: 2);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 4, pinned: true);
  final speaker = _a('live_room.speaker', Icons.speaker_phone_rounded, 'lr_speaker'.tr, active: true);
  final pause = _a('live_room.pause_recording', Icons.pause_circle_outline_rounded, 'lr_pause'.tr, active: true, color: LivePalette.warning);
  return LiveControlBar(
    primary: [mic, cam, share, react, hands, chat],
    secondary: [speaker, pause],
    groups: [
      [mic, cam, speaker],
      [share, pause],
      [react, hands, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
    rec: LiveRecBadge.recording,
    onLobby: () {},
    waitingCount: 1,
    lobbyAttention: 1,
  );
}

Widget _studentBar(LiveShareButton mode) {
  final mic = _a('live_room.mic', Icons.mic_off_rounded, 'lr_unmute'.tr, off: true);
  final cam = _a('live_room.camera', Icons.videocam_rounded, 'lr_camera'.tr, active: true);
  final share = ControlsWidgetState.shareAction(mode, onTap: () {})!;
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final hand = _a('live_room.hand', Icons.back_hand_outlined, 'lr_raise_hand'.tr);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 2, pinned: true);
  final speaker = _a('live_room.speaker', Icons.speaker_phone_rounded, 'lr_speaker'.tr, active: true);
  return LiveControlBar(
    primary: [mic, cam, share, react, hand, chat],
    secondary: [speaker],
    groups: [
      [mic, cam, speaker],
      [share],
      [react, hand, chat],
    ],
    end: _a('live_room.end', Icons.call_end_rounded, 'lr_end'.tr),
  );
}

Widget _hostScene(BuildContext context) {
  final student = _tr('سارة أحمد', 'Sara Ahmed');
  return Stack(fit: StackFit.expand, children: [
    SafeArea(
      child: Column(children: [
        Expanded(
          child: _stage(
            content: _sharedSlide(),
            topStart: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _presenterPill(_tr('عمر خالد', 'Omar Khaled')),
              LiveStopShareChip(onTap: () {}),
            ]),
            bottomStart: LiveChatToast(
              data: LiveChatToastData(
                id: 'm1',
                name: student,
                text: _tr('أستاذ، ممكن ترجع للشريحة السابقة؟ فاتتني معادلة المشتقة الثانية.',
                    'Could you go back to the previous slide? I missed the second-derivative formula.'),
                more: 3,
              ),
              onOpen: () {},
              onDismiss: () {},
            ),
          ),
        ),
        _hostBar(),
      ]),
    ),
    // the request dialog (its scrim + card), as showLiveShareRequestDialog draws it
    ColoredBox(color: LivePalette.shade(0.55)),
    Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LiveShareRequestCard(
          name: student,
          note: LiveShareAcceptNote.other,
          presenterName: _tr('عمر خالد', 'Omar Khaled'),
          othersWaiting: 1,
          remaining: const Duration(seconds: 22),
          onAccept: () {},
          onReject: () {},
        ),
      ),
    ),
  ]);
}

Widget _studentScene(BuildContext context) {
  final teacher = _tr('د. منى السيد', 'Dr. Mona Elsayed');
  return SafeArea(
    child: Column(children: [
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          _stage(
            content: Center(child: LiveAvatar(name: teacher, size: 120, isSpeaking: true, audioLevel: 0.6)),
            topStart: _presenterPill(teacher),
          ),
          PositionedDirectional(
            top: 24,
            end: 24,
            child: SizedBox(
              width: 150,
              height: 94,
              child: LiveMiniBoxLayout(name: teacher, onExpand: () {}, onToggleMic: () {}, onLeave: () {}, attention: 3),
            ),
          ),
        ]),
      ),
      _studentBar(LiveShareButton.request),
      _studentBar(LiveShareButton.requested),
    ]),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(BuildContext) scene) async {
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
            matchesGoldenFile('goldens/live_share_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

  testWidgets('host', (t) => _render(t, 'host', _hostScene));
  testWidgets('student', (t) => _render(t, 'student', _studentScene));
}
