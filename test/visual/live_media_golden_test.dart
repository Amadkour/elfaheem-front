// Visual review renders of the live media tuning UI (D-090; compared by eye, like the other test/visual files; NOT a
// CI suite):
//
//   flutter test test/visual/live_media_golden_test.dart --update-goldens
//
// → test/visual/goldens/live_media_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   weak        a student's room on a weak link: the teacher's (lowered) camera on the stage, the badge column with
//               "Poor connection — video quality lowered", the bar.
//   recovering  the same room one step back up: "Connection improving — quality coming back".
//   audio_only  `weak_network: audio_first` below the threshold: avatars, the audio-only card with Show video.
//   audio_share the same with a shared screen kept at the lowest layer (the card says so).
//   prejoin     a student's pre-join page with the camera off by the admin default and the hint with Turn on.
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
import 'package:flutter_education_app/features/live/live_net_pill.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_avatar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_control_bar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/participant.dart' show ParticipantTileLayout;
import 'package:flutter_education_app/features/live/room/widgets/participant_info.dart' show LiveNetQuality;
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

/// A stand-in for a (slightly soft, lowered-layer) camera frame: a warm room, a person, a bookshelf.
class _FakeCamera extends StatelessWidget {
  const _FakeCamera();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final head = h * 0.2;
        return Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6B5A4E), Color(0xFF3E3A44), Color(0xFF26252E)],
              ),
            ),
          ),
          // shelf
          for (var i = 0; i < 5; i++)
            Positioned(
              left: w * 0.06 + i * w * 0.045,
              top: h * 0.16,
              width: w * 0.035,
              height: h * (0.18 + (i % 3) * 0.03),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: [const Color(0xFF8C6D4F), const Color(0xFF4F6A7A), const Color(0xFF7A4F4F)][i % 3].withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          // shoulders
          Positioned(
            left: w * 0.5 - h * 0.34,
            width: h * 0.68,
            bottom: -h * 0.12,
            height: h * 0.46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2F4A6B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(h * 0.3)),
              ),
            ),
          ),
          // head
          Positioned(
            left: w * 0.5 - head * 0.8,
            top: h * 0.26,
            width: head * 1.6,
            height: head * 2,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [Color(0xFFD9A982), Color(0xFFB98563)], radius: 0.8),
                borderRadius: BorderRadius.all(Radius.elliptical(100, 120)),
              ),
            ),
          ),
          // a lowered layer looks soft
          ColoredBox(color: LivePalette.ink(0.04)),
        ]);
      });
}

Widget _sharedSlide() => Container(
      decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(19)),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, c) {
        // Sized from the slide's height, so a phone's small slide stays inside it.
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

/// The room's badge column (top-end): (i) + minimize, the session clock, then [extra].
Widget _badges(List<Widget> extra) {
  Widget chip(IconData icon) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: LivePalette.shade(0.5), shape: BoxShape.circle, border: Border.all(color: LivePalette.glassBorder)),
        child: Icon(icon, size: 15, color: LivePalette.textMid),
      );
  final clock = Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: LivePalette.shade(0.58),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: LivePalette.glassBorder),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.schedule_rounded, size: 12, color: LivePalette.textMid),
      const SizedBox(width: 6),
      Text('24:18', style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w700, color: LivePalette.textMid)),
    ]),
  );
  // Like the room: the column hugs the physical right edge in both languages.
  return Column(crossAxisAlignment: CrossAxisAlignment.end, textDirection: TextDirection.ltr, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [chip(Icons.info_outline_rounded), const SizedBox(width: 6), chip(Icons.picture_in_picture_alt_rounded)]),
    const SizedBox(height: 6),
    clock,
    for (final w in extra) ...[const SizedBox(height: 6), w],
  ]);
}

Widget _stage({required Widget content, List<Widget> badges = const [], Widget? bottom}) => Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -0.3), radius: 1.2, colors: [LivePalette.surfaceHi, LivePalette.bg]),
            ),
          ),
          content,
          Positioned(top: 14, right: 14, child: _badges(badges)),
          if (bottom != null)
            LayoutBuilder(builder: (context, c) => Stack(children: [
                  PositionedDirectional(start: 12, end: 12, bottom: c.maxWidth >= 900 ? 14 : 64, child: Center(child: bottom)),
                ])),
          // the participant count badge (bottom-end)
          Positioned(
            bottom: 14,
            right: 14,
            child: Container(
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
            ),
          ),
        ]),
      ),
    );

LiveControlAction _a(String key, IconData icon, String label, {String? compact, bool active = false, int badge = 0, bool pinned = false, bool off = false}) =>
    LiveControlAction(key: ValueKey(key), icon: icon, label: label, compactLabel: compact, active: active, badge: badge, pinned: pinned, off: off, onTap: () {});

Widget _studentBar() {
  final mic = _a('live_room.mic', Icons.mic_off_rounded, 'lr_unmute'.tr, off: true);
  final cam = _a('live_room.camera', Icons.videocam_off_rounded, 'lr_cam_off'.tr, compact: 'lr_camera'.tr, off: true);
  final react = _a('live_room.reactions', Icons.add_reaction_outlined, 'lr_react'.tr);
  final hand = _a('live_room.hand', Icons.back_hand_outlined, 'lr_raise_hand'.tr);
  final chat = _a('live_room.chat', Icons.chat_bubble_outline_rounded, 'lr_chat'.tr, badge: 2, pinned: true);
  final speaker = _a('live_room.speaker', Icons.speaker_phone_rounded, 'lr_speaker'.tr, active: true);
  return LiveControlBar(
    primary: [mic, cam, react, hand, chat],
    secondary: [speaker],
    groups: [
      [mic, cam, speaker],
      [react, hand, chat],
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
      body: SafeArea(child: Column(children: [Expanded(child: stage), _studentBar()])),
    ),
  );
}

String get _teacher => _tr('د. منى السيد', 'Dr. Mona Elsayed');

Widget _teacherTile() => Padding(
      padding: const EdgeInsets.fromLTRB(10, 56, 10, 56),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ParticipantTileLayout(
            name: _teacher,
            isHost: true,
            isSpeaking: true,
            audioLevel: 0.5,
            camOn: true,
            quality: LiveNetQuality.poor,
            radius: 18,
            child: const _FakeCamera(),
          ),
        ),
      ),
    );

Widget _weakScene(BuildContext context) => _room(context, _stage(content: _teacherTile(), badges: const [LiveNetPill()]));

Widget _recoveringScene(BuildContext context) =>
    _room(context, _stage(content: _teacherTile(), badges: const [LiveNetPill(recovering: true)]));

Widget _avatars() {
  final names = [
    _teacher,
    _tr('سارة أحمد', 'Sara Ahmed'),
    _tr('عمر خالد', 'Omar Khaled'),
    _tr('ليلى حسن', 'Laila Hassan'),
  ];
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 70, 16, 150),
    child: Center(
      child: Wrap(alignment: WrapAlignment.center, spacing: 28, runSpacing: 22, children: [
        for (var i = 0; i < names.length; i++)
          Column(mainAxisSize: MainAxisSize.min, children: [
            LiveAvatar(name: names[i], size: i == 0 ? 112 : 72, isSpeaking: i == 0, audioLevel: i == 0 ? 0.55 : 0),
            const SizedBox(height: 8),
            Text(names[i], style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, fontWeight: FontWeight.w700, color: LivePalette.textMid)),
          ]),
      ]),
    ),
  );
}

Widget _audioOnlyScene(BuildContext context) =>
    _room(context, _stage(content: _avatars(), bottom: LiveAudioOnlyCard(onShowVideo: () {})));

Widget _audioShareScene(BuildContext context) => _room(
      context,
      _stage(
        content: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 170),
          child: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _sharedSlide())),
        ),
        bottom: LiveAudioOnlyCard(onShowVideo: () {}, keepsScreen: true),
      ),
    );

Widget _prejoinScene(BuildContext context) => Scaffold(
      backgroundColor: context.colors.background,
      body: PreJoinLayout(
        title: _tr('محاضرة الفيزياء — الأسبوع السابع', 'Physics lecture — week 7'),
        subtitle: 'lr_ready_to_join'.tr,
        isTeacher: false,
        userName: _tr('سارة أحمد', 'Sara Ahmed'),
        preview: null,
        micOn: true,
        camOn: false,
        micLevel: 0.5,
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
        cameraOffHint: true,
      ),
    );

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
            matchesGoldenFile('goldens/live_media_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

  testWidgets('weak', (t) => _render(t, 'weak', _weakScene));
  testWidgets('recovering', (t) => _render(t, 'recovering', _recoveringScene));
  testWidgets('audio_only', (t) => _render(t, 'audio_only', _audioOnlyScene));
  testWidgets('audio_share', (t) => _render(t, 'audio_share', _audioShareScene));
  testWidgets('prejoin', (t) => _render(t, 'prejoin', _prejoinScene));
}
