// Visual review renders of "Add answer sheets" (scan_sources.dart, scan_upload_view.dart), compared by eye like the
// other test/visual files (NOT a CI suite). The PNGs go OUTSIDE the repo:
//
//   SRC_RENDER_DIR=<dir> flutter test test/visual/scan_sources_golden_test.dart --update-goldens [--plain-name summary]
//
// → <dir>/scansrc_<scene>_<width>_<lang>_<light|dark>.png
//   sheet_android   the source sheet on the Android app: camera, gallery, files, a scanner's folder
//   sheet_ios       the source sheet on the iOS app: no folder, the hint to use Files
//   summary         a scanner's folder before it is sent: 12 found, 9 images, 3 PDFs, 2 skipped with the reason
//   progress        "Uploading 3 of 12 files"
//   failures        two files that did not go (Retry) above the batch's "X of N papers processed"
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_sources.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_upload_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
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
final _dir = (Platform.environment['SRC_RENDER_DIR'] ?? '${Directory.systemTemp.path}/scan_src_renders').replaceAll('\\', '/');

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
      home: child,
    ),
  );
}

Widget _page(String title, Widget body) => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(title)),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.all(16), children: [body])),
        ),
      ),
    );

/// The scanned-pages page with the source sheet opened over it.
class _WithSheet extends StatefulWidget {
  const _WithSheet(this.platform, {this.camera = true});
  final ScanPlatform platform;
  final bool camera;
  @override
  State<_WithSheet> createState() => _WithSheetState();
}

class _WithSheetState extends State<_WithSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => showScanSourceSheet(context, camera: widget.camera, platform: widget.platform, picker: (s, {bool single = false}) async => null));
  }

  @override
  Widget build(BuildContext context) => _page(
      t('الأوراق الممسوحة', 'Scanned pages'),
      OmrToolsPanel(entries: [
        OmrToolEntry(id: 'camera', icon: Icons.document_scanner_outlined, title: t('التصوير بالكاميرا', 'Scan with camera'), subtitle: '', onTap: () {}),
        OmrToolEntry(id: 'upload', icon: Icons.upload_file_rounded, title: t('رفع الأوراق', 'Upload papers'), subtitle: '', onTap: () {}),
      ]));
}

ScanSourceFile _f(String path, int size) =>
    ScanSourceFile(name: path.split('/').last, path: path, size: size, read: () async => Uint8List(0));

const _folder = 'Grade 10 · Physics midterm';

ScanPlan _plan() => planScanFiles([
      for (var i = 1; i <= 9; i++) _f('Class A/page$i.jpg', 2100000 + i * 37000),
      for (var i = 1; i <= 3; i++) _f('Class B/batch $i.pdf', 4300000 + i * 90000),
      _f('Class B/scan settings.xml', 2000),
      _f('Class A/empty.png', 0),
      _f('.DS_Store', 6000),
    ], folder: _folder);

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {int frames = 8}) async {
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
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/scansrc_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('sheet_android', (t0) => _render(t0, 'sheet_android', () => const _WithSheet(ScanPlatform(web: false, os: TargetPlatform.android))));
  testWidgets('sheet_ios', (t0) => _render(t0, 'sheet_ios', () => const _WithSheet(ScanPlatform(web: false, os: TargetPlatform.iOS))));
  testWidgets('sheet_desktop_web', (t0) => _render(t0, 'sheet_desktop_web', () => const _WithSheet(ScanPlatform(web: true, os: TargetPlatform.windows), camera: false)));
  testWidgets('summary', (t0) => _render(t0, 'summary', () => _page(t('معالجة الأوراق', 'Processing papers'),
      ScanPickSummary(plan: _plan(), source: ScanSource.folder, onUpload: () {}, onChooseAgain: () {}))));
  testWidgets('progress', (t0) => _render(t0, 'progress', () => _page(t('معالجة الأوراق', 'Processing papers'),
      const ScanUploadProgress(done: 3, total: 12, current: 'Class A/page4.jpg'))));
  testWidgets('failures', (t0) => _render(t0, 'failures', () {
        final failures = [
          ScanFailure(_f('Class B/batch 2.pdf', 4400000), t('ملف PDF غير صالح أو محمي بكلمة مرور', 'The PDF is damaged or protected by a password')),
          ScanFailure(_f('Class A/IMG_0412.heic', 3100000), t('صورة HEIC لا يفتحها هذا الجهاز — احفظها بصيغة JPEG', 'A HEIC photo this device cannot open — save it as JPEG')),
        ];
        return _page(
            t('معالجة الأوراق', 'Processing papers'),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ScanUploadFailures(failures: failures, onRetry: () {}),
              const SizedBox(height: 16),
              ScanProgressView(
                headline: t('عولجت 4 أوراق من 10', '4 of 10 papers processed'),
                done: 4,
                total: 10,
                finished: false,
                graded: 3,
                review: 1,
                duplicates: 2,
                onMore: () {},
              ),
            ]));
      }));
}
