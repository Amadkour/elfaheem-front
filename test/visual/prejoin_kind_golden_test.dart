// Visual review renders of the pre-join page by room kind (D-106), compared by eye like the other test/visual files
// (NOT a CI suite):
//
//   flutter test test/visual/prejoin_kind_golden_test.dart --update-goldens [--plain-name meeting]
//
// → test/visual/goldens/prejoin_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   meeting_participant  a student's free meeting from a link: «انضم للاجتماع», Participant, camera off by default
//   meeting_host         "Meet now": the owner is the Host, camera on, no "may be recorded" note
//   session_student      a course live session keeps «انضم للحصة» / Student
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/live_room_words.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/prejoin_layout.dart';
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
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// A stand-in for the camera: a soft gradient with a head-and-shoulders silhouette.
Widget _fakeCamera() => Builder(builder: (context) {
      final c = context.colors;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.primary.withValues(alpha: 0.55), LivePalette.bg],
          ),
        ),
        child: Align(
          alignment: const Alignment(0, 0.6),
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: FittedBox(child: Icon(Icons.person_rounded, color: LivePalette.ink(0.35))),
          ),
        ),
      );
    });

Widget _scene(String name) {
  final meeting = name.startsWith('meeting');
  final host = name == 'meeting_host';
  final kind = meeting ? LiveRoomKind.meeting : LiveRoomKind.session;
  final title = switch (name) {
    'meeting_host' => tr('اجتماع الخميس ٣٠ أكتوبر ١٢:٠٥ م', 'Meeting · Thu 30 Oct 12:05 PM'),
    'meeting_participant' => tr('مراجعة مشروع التخرج', 'Graduation project review'),
    _ => tr('تراكيب البيانات — المحاضرة السابعة', 'Data structures — lecture 7'),
  };
  return PreJoinLayout(
    title: title,
    subtitle: translate('lr_ready_to_join'),
    roomKind: kind,
    isTeacher: false,
    isHost: host,
    userName: tr('سارة أحمد', 'Sara Ahmed'),
    preview: host ? _fakeCamera() : null,
    micOn: true,
    camOn: host,
    micLevel: 0.5,
    onToggleMic: () {},
    onToggleCam: () {},
    mics: [('m1', tr('الميكروفون الافتراضي', 'Default microphone')), ('m2', 'USB Microphone')],
    cams: [('c1', tr('الكاميرا المدمجة', 'Integrated camera'))],
    selectedMic: 'm1',
    selectedCam: 'c1',
    onMicChanged: (_) {},
    onCamChanged: (_) {},
    busy: false,
    onJoin: () {},
    onBack: () {},
    cameraOffHint: !host,
    onPreviewShape: (_) {},
  );
}

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(builder: (context) {
        LivePalette.sync(context);
        return Scaffold(backgroundColor: context.colors.background, body: child);
      }),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, {List<bool> modes = const [false, true]}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in modes) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(_scene(name), dark: dark));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/prejoin_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  testWidgets('meeting participant', (tester) => _render(tester, 'meeting_participant'));
  testWidgets('meeting host', (tester) => _render(tester, 'meeting_host', modes: const [false]));
  testWidgets('session student', (tester) => _render(tester, 'session_student', modes: const [false]));
}
