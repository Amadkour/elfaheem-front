// VISUAL review renders of the Downloads page and the upload footer (editorial theme), compared by eye like the other
// test/visual files (NOT a CI suite):
//
//   flutter test test/visual/session_downloads_golden_test.dart --update-goldens [--plain-name downloads]
//
// → test/visual/goldens/session_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900, ar / en.
//   downloads        the real DownloadsScreen over three saved lectures (a temp offline folder, no network)
//   downloads_empty  the same with nothing saved
//   upload           the upload footer, folded and unfolded, over a plain page
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter_education_app/features/shared/upload/upload_progress_footer.dart';
import 'package:flutter_education_app/features/shared/upload/upload_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
late Directory _support;

/// Three saved lectures in the offline folder the service reads (index.json + an .enc per copy).
void _seedOffline({required bool empty}) {
  final dir = Directory('${_support.path}/offline')..createSync(recursive: true);
  for (final f in dir.listSync()) {
    f.deleteSync();
  }
  if (empty) {
    File('${dir.path}/index.json').writeAsStringSync('{}');
    return;
  }
  final now = DateTime.now();
  Map<String, dynamic> meta(int sid, int mid, String title, String desc, String tier, int mb, int ageDays, int leftDays) => {
        'sessionId': sid,
        'materialId': mid,
        'title': title,
        'description': desc,
        'courseId': 7,
        'tier': tier,
        'size': mb * 1024 * 1024,
        'createdAt': now.subtract(Duration(days: ageDays)).millisecondsSinceEpoch,
        'expiresAt': now.add(Duration(days: leftDays, hours: 2)).millisecondsSinceEpoch,
      };
  final index = {
    '4_11': meta(4, 11, 'المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته', 'التفاضل والتكامل ٢', 'medium', 182, 1, 13),
    '4_10': meta(4, 10, 'Lecture 2 — Integration by substitution', 'Calculus II · Dr. Sara Ahmed', 'high', 412, 2, 6),
    '5_21': meta(5, 21, 'Thermodynamics, part one: heat, work and the first law', 'General physics', 'low', 64, 4, 1),
  };
  File('${dir.path}/index.json').writeAsStringSync(jsonEncode(index));
  for (final id in index.keys) {
    File('${dir.path}/$id.enc').writeAsBytesSync(List.filled(16, 1));
  }
}

Widget _host(Widget page, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  theme.debugUseColors(
      jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
  final rtl = AppConfig.lang == 'ar';
  return ChangeNotifierProvider<ThemeConfigProvider>.value(
    value: theme,
    child: ThemeConfigScope(
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
        home: page,
      ),
    ),
  );
}

UploadTask _task(String name, UploadStatus status, {double p = 0, bool retry = false}) {
  final t = UploadTask(
    sessionId: 4,
    fileName: name,
    cancelToken: CancelToken(),
    dio: Dio(),
    path: '',
    endpoint: '',
    fields: const {},
  )
    ..status = status
    ..totalBytes = 100
    ..sentBytes = (p * 100).round()
    ..canRetry = retry;
  return t;
}

Future<void> _render(WidgetTester tester, String name, Widget Function(bool dark) build, {void Function()? before}) async {
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
          before?.call();
          await tester.pumpWidget(build(dark));
          // the offline folder is read with real file IO
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
            await tester.pump(const Duration(milliseconds: 200));
          }
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/session_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
    _support = Directory.systemTemp.createTempSync('nb_dl_visual');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => _support.path);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('downloads', (t) async {
    _seedOffline(empty: false);
    await _render(t, 'downloads', (dark) => _host(const DownloadsScreen(), dark: dark));
  });

  testWidgets('downloads empty', (t) async {
    _seedOffline(empty: true);
    await _render(t, 'downloads_empty', (dark) => _host(const DownloadsScreen(), dark: dark));
  });

  testWidgets('upload', (t) async {
    final tasks = [
      _task('lecture-3-integration-by-parts.mp4', UploadStatus.uploading, p: 0.42),
      _task('ملخص المحاضرة الأولى.pdf', UploadStatus.success),
      _task('worksheet-week-2.docx', UploadStatus.failed, retry: true),
    ];
    Widget footer(bool expanded) => UploadProgressFooterView(
          tasks: tasks,
          expanded: expanded,
          overallProgress: 0.42,
          activeCount: 1,
          onToggle: () {},
          onCancel: (_) {},
          onRetry: (_) {},
          onDismiss: (_) {},
        );
    await _render(
      t,
      'upload',
      (dark) => _host(
        Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            body: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              footer(false),
              const SizedBox(height: 24),
              footer(true),
            ]),
          ),
        ),
        dark: dark,
      ),
    );
  });
}
