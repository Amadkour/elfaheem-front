// Visual review renders of the video Studio (D-820), compared by eye like the other test/visual files (NOT a CI suite):
// phone 390×844 and desktop 1440×900, Arabic and English, light and dark. The images go to STUDIO_RENDER_DIR when it is
// set, else test/visual/goldens.
//
//   STUDIO_RENDER_DIR=<dir> flutter test test/visual/studio_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'studio_scenes.dart';
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

/// A filmstrip of 25 tiles that look like slides of a lecture.
Future<ui.Image> _sprite() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const tw = 160.0, th = 90.0;
  for (var i = 0; i < 25; i++) {
    final r = Rect.fromLTWH(i * tw, 0, tw, th);
    final hue = (200 + i * 7) % 360.0;
    c.drawRect(r, Paint()..color = HSLColor.fromAHSL(1, hue, 0.35, 0.30 + (i % 5) * 0.04).toColor());
    c.drawRect(Rect.fromLTWH(r.left + 14, 16, tw - 28, 10), Paint()..color = const Color(0xCCFFFFFF));
    for (var k = 0; k < 3; k++) {
      c.drawRect(Rect.fromLTWH(r.left + 14, 36.0 + k * 12, tw - 60 - k * 12, 5), Paint()..color = const Color(0x88FFFFFF));
    }
    c.drawCircle(Offset(r.right - 26, 70), 12, Paint()..color = const Color(0xFFE8B98A));
  }
  return rec.endRecording().toImage((tw * 25).toInt(), th.toInt());
}

Uint8List _wave() => Uint8List.fromList([for (var i = 0; i < 2000; i++) (40 + 120 * ((i * 37 % 97) / 97) * (i % 50 < 6 ? 0.2 : 1)).round()]);

final _shot = GlobalKey();

Widget _host(Widget child, {required bool dark, required bool rtl}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: displayTheme(theme.materialTheme(dark: false), const DisplayPrefs()),
      darkTheme: displayTheme(theme.materialTheme(dark: true), const DisplayPrefs()),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

RecordItem _item() => RecordItem.fromJson({
      'recording_id': 1,
      'kind': 'meeting',
      'status': 'done',
      'quality': '720p',
      'destination': 'google_drive',
      'size': 734003200,
      'duration_seconds': 3125.0,
      'created_at': '2026-11-08T09:00:00',
      'title': 'Lesson 3 — Fractions and decimals, with the whole class',
      'can_edit': true,
      'can_play': true,
    })!;

void main() {
  late ui.Image sprite;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  Future<void> shot(WidgetTester t, String name, StudioScene scene, {required Size size, required String lang, required bool dark}) async {
    AppConfig.lang = lang;
    AppConfig.disableList = [];
    final ar = lang == 'ar';
    sprite = await t.runAsync(_sprite) as ui.Image;
    debugDisableShadows = false;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(studioSceneView(scene, item: _item(), sprite: sprite, waveform: _wave()), dark: dark, rtl: ar));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final dir = Platform.environment['STUDIO_RENDER_DIR'];
    final file = 'studio_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png';
    await expectLater(find.byKey(_shot), matchesGoldenFile(dir == null ? 'goldens/$file' : Uri.file('$dir/$file').toString()));
    await t.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }

  for (final scene in StudioScene.values) {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['en', 'ar']) {
        for (final dark in const [false, true]) {
          // every scene in English light; the full matrix only for the main edit scene
          if (scene != StudioScene.edit && (lang == 'ar') == dark) continue;
          testWidgets('${scene.name} ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}', (t) async {
            await shot(t, scene.name, scene, size: size, lang: lang, dark: dark);
          });
        }
      }
    }
  }
}
