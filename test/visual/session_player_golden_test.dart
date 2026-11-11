// VISUAL review renders of the course video player's chrome (editorial theme), compared by eye like the other
// test/visual files (NOT a CI suite):
//
//   flutter test test/visual/session_player_golden_test.dart --update-goldens [--plain-name chrome]
//
// → test/visual/goldens/session_player_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900, ar / en,
//   with the built-in Warm Editorial palette and real fonts.
//   chrome    the real VideoPlayerScreen over a paused lecture (top bar, play row, seek bar, chips)
//   quality   the same with the quality sheet open
//   speed     the same with the speed sheet open
//   lectures  the lecture list sheet
//   overlays  next up (counting down), resume chip, level HUD and a caption over a black frame
//   gates     the course page's session pieces: track tabs, the exam gate in its states, action buttons
//   add       the teacher's Add material sheet (phone sheet / wide card) with its header button
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/media_focus.dart';
import 'package:flutter_education_app/features/shared/session/material/components/add_material_sheet.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_exam_tile.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_shared_widgets.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/features/student/courses/details/session_exam_gate.dart';
import 'package:flutter_education_app/features/shared/session/video/video_player_screen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/vod_listen_test.dart' show FakeVc;
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

SessionMaterialModel _lecture(int id, {String? name, bool done = false, int secs = 2900, bool urls = true}) => SessionMaterialModel(
      id: id,
      sessionId: 4,
      name: name ?? _tr('المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته', 'Lecture 3 — Integration by parts and its uses'),
      description: _tr('التفاضل والتكامل ٢ · د. سارة أحمد', 'Calculus II · Dr. Sara Ahmed'),
      type: SessionMaterialType.video,
      order: id,
      createdAt: DateTime(2026),
      completed: done,
      durationSeconds: secs,
      urlHigh: urls ? 'https://media.test/high.mp4' : null,
      urlMedium: urls ? 'https://media.test/medium.mp4' : null,
      urlLow: urls ? 'https://media.test/low.mp4' : null,
      rawUrlHigh: urls ? 'https://media.test/high.mp4' : null,
      rawUrlMedium: urls ? 'https://media.test/medium.mp4' : null,
      rawUrlLow: urls ? 'https://media.test/low.mp4' : null,
    );

List<SessionMaterialModel> _playlist() => [
      _lecture(9, name: _tr('المحاضرة الأولى — مراجعة الاشتقاق', 'Lecture 1 — Derivatives, a review'), done: true, secs: 2410),
      _lecture(10, name: _tr('المحاضرة الثانية — التكامل بالتعويض', 'Lecture 2 — Integration by substitution'), done: true, secs: 3125),
      _lecture(11),
      _lecture(12, name: _tr('المحاضرة الرابعة — الكسور الجزئية', 'Lecture 4 — Partial fractions'), secs: 3640),
      _lecture(13, name: _tr('المحاضرة الخامسة — التكاملات المعتلة وتقاربها', 'Lecture 5 — Improper integrals and convergence'), secs: 2780),
    ];

Widget _host(Widget Function(BuildContext) page, {required bool dark, required double statusBar}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  // the built-in default palette: Warm Editorial (D-610)
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
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: statusBar), viewPadding: EdgeInsets.only(top: statusBar)),
          child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        ),
      ),
      home: Builder(builder: page),
    ),
  );
}

Widget _player({bool error = false}) {
  final list = _playlist();
  final m = error ? _lecture(11, urls: false) : list[2];
  final vc = FakeVc(duration: const Duration(minutes: 48, seconds: 20), at: const Duration(minutes: 12, seconds: 3));
  return VideoPlayerScreen(
    material: m,
    playlist: error ? null : list,
    resume: error ? null : VodListenHandoff(controller: vc, material: m, current: m, variant: m.videoVariants.last),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(bool phone, bool dark) build,
    {Future<void> Function(WidgetTester t)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          MediaFocus.reset();
          VodListenSession.instance.debugReset();
          await tester.pumpWidget(build(size.width < 600, dark));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/session_player_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    VodListenSession.instance.debugReset();
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('floating'), (_) async => null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> playerScene(WidgetTester t, String name, {Future<void> Function(WidgetTester t)? act, bool error = false}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS; // no Android PiP timer in tests
    try {
      await _render(t, name, (phone, dark) => _host((_) => _player(error: error), dark: dark, statusBar: phone ? 44 : 0), act: act);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('chrome', (t) => playerScene(t, 'chrome'));
  testWidgets('quality', (t) => playerScene(t, 'quality', act: (t) async => t.tap(find.text('1080p').last)));
  testWidgets('speed', (t) => playerScene(t, 'speed', act: (t) async => t.tap(find.text('normal_speed'.tr).last)));

  testWidgets('lectures', (t) async {
    await _render(
      t,
      'lectures',
      (phone, dark) => _host(
        (context) => Scaffold(
          backgroundColor: VodInk.letterbox,
          body: Center(
            child: TextButton(
              onPressed: () => showVodLectureList(context, items: _playlist(), currentId: 11, onSelect: (_) {}),
              child: const Text('open'),
            ),
          ),
        ),
        dark: dark,
        statusBar: phone ? 44 : 0,
      ),
      act: (t) async => t.tap(find.text('open')),
    );
  });

  testWidgets('overlays', (t) async {
    await _render(
      t,
      'overlays',
      (phone, dark) => _host(
        (context) => Scaffold(
          backgroundColor: VodInk.letterbox,
          body: Stack(fit: StackFit.expand, children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 96),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  VodResumeChip(at: const Duration(minutes: 42, seconds: 7), onStartOver: () {}),
                  const SizedBox(height: 16),
                  const VodLevelHud(brightness: false, value: 0.62),
                ]),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VodCaption(text: _tr('إذن نختار u بحيث يصبح تكامل v du أبسط من التكامل الأصلي',
                    'So we pick u so that the integral of v du is simpler than the one we started with')),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VodNextUpCard(next: _playlist()[3], seconds: 3, maxWidth: phone ? 358 : 360, onPlay: () {}, onCancel: () {}),
              ),
            ),
          ]),
        ),
        dark: dark,
        statusBar: phone ? 44 : 0,
      ),
    );
  });

  testWidgets('gates', (t) async {
    SessionExamInfo exam(Map<String, dynamic> j) => SessionExamInfo.fromJson({'question_count': 10, ...j});
    final pending = exam({'id': 1, 'name': _tr('اختبار التكامل بالتجزئة', 'Integration by parts quiz'), 'passing_score': 60, 'remaining_submissions': 2});
    final retried = exam({'id': 2, 'name': _tr('اختبار قصير', 'Short quiz'), 'passing_score': 50, 'attempted': true, 'best_percentage': 40, 'remaining_submissions': 1});
    final passed = exam({'id': 3, 'name': _tr('اختبار الوحدة الأولى', 'Unit 1 test'), 'passing_score': 50, 'attempted': true, 'passed': true, 'best_percentage': 86});
    final out = exam({'id': 4, 'name': _tr('اختبار الوحدة الثانية', 'Unit 2 test'), 'passing_score': 50, 'attempted': true, 'best_percentage': 30, 'remaining_submissions': 0});
    await _render(
      t,
      'gates',
      (phone, dark) => _host(
        (context) => Scaffold(
          backgroundColor: context.colors.background,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                SessionTrackTabs(value: 'lecture', lectures: 16, sections: 9, onChanged: (_) {}),
                const SizedBox(height: 24),
                SessionExamTile(gate: SessionExamGate([pending]), isTeacher: false, onOpen: () {}),
                SessionExamTile(gate: SessionExamGate([retried, pending]), isTeacher: false, onOpen: () {}),
                SessionExamTile(gate: SessionExamGate([passed]), isTeacher: false, onOpen: () {}),
                SessionExamTile(gate: SessionExamGate([out]), isTeacher: false, onOpen: () {}),
                SessionExamTile(gate: SessionExamGate([pending]), isTeacher: true, onOpen: () {}),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SessionActionBtn(icon: Icons.videocam_rounded, label: _tr('دخول الغرفة', 'Enter room'), color: context.colors.danger, filled: true, onTap: () {}),
                  SessionActionBtn(icon: Icons.how_to_reg_rounded, label: _tr('الحضور', 'Attendance'), color: context.colors.primary, onTap: () {}),
                  SessionActionBtn(icon: Icons.upload_rounded, label: 'Upload', color: context.colors.success, loading: true),
                ]),
              ]),
            ),
          ),
        ),
        dark: dark,
        statusBar: phone ? 44 : 0,
      ),
    );
  });

  testWidgets('add', (t) async {
    await _render(
      t,
      'add',
      (phone, dark) => _host(
        (context) => Scaffold(
          backgroundColor: context.colors.background,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(alignment: AlignmentDirectional.centerEnd, child: AddMaterialButton(sessionId: 4)),
              ),
              const Spacer(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AddMaterialSheet(sessionId: 4, isWide: !phone),
                ),
              ),
            ]),
          ),
        ),
        dark: dark,
        statusBar: 0,
      ),
    );
  });
}
