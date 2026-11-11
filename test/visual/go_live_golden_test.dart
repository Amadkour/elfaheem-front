// Visual review renders of the instructor home's "Go live" (D-091), compared by eye like the other test/visual
// files (NOT a CI suite):
//
//   flutter test test/visual/go_live_golden_test.dart --update-goldens [--plain-name sheet]
//
// → test/visual/goldens/go_live_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   header     the home header: "Go live", then "Return to live" while a room of mine runs
//   scheduled  the sheet over the home: four courses, the course's session in 12 min offered first
//   new        no session near now: "New live session now" with its optional title
//   live       a room of the course runs: "Rejoin the live" (no Record switch)
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/teacher/home/go_live.dart';
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart' show TeacherHomeHero;
import 'package:flutter_education_app/features/teacher/sessions/model/live_response_model.dart';
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// 12:00 in Cairo on a Thursday.
final _now = DateTime.utc(2026, 10, 29, 10, 0);

class _Api implements GoLiveApi {
  _Api(this.rows);
  final List<GoLiveSession> rows;

  @override
  Future<List<GoLiveSession>> sessions(int courseId) async => rows;
  @override
  Future<int> create({required int courseId, required String title, required DateTime startsAt, int minutes = 60, required bool record}) async => 1;
  @override
  Future<void> setRecord(int sessionId, bool record) async {}
  @override
  Future<LiveResponseModel> start(int sessionId, {bool? record}) async => LiveResponseModel(sessionId: sessionId, url: '', token: '');
  @override
  Future<void> end(int sessionId) async {}
}

List<GoLiveCourse> _courses() => [
      GoLiveCourse(id: 1, title: tr('تراكيب البيانات', 'Data structures'), students: 420),
      GoLiveCourse(id: 2, title: tr('معمل الشبكات', 'Networks lab'), students: 380),
      GoLiveCourse(id: 3, title: tr('الذكاء الاصطناعي', 'Artificial intelligence'), students: 610),
      GoLiveCourse(id: 4, title: tr('تعلم الآلة المتقدم', 'Advanced machine learning'), students: 0, published: false),
    ];

/// A slice of the instructor home behind the sheet: the real hero (the forest greeting card, Go live), enough
/// to read the page under it.
Widget _homeBehind({bool live = false}) => ListView(padding: EdgeInsets.zero, children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TeacherHomeHero(
              name: tr('أحمد حمدي', 'Ahmed Hamdy'),
              subtitle: tr('٣ حصص اليوم · التالية ١٢:١٢ م', '3 sessions today · next at 12:12 PM'),
              ring: 1 / 3,
              switcher: Text(tr('الحساب الشخصي', 'Personal')),
              goLive: GoLiveButton(live: live, onHero: true, onTap: () {}),
            ),
            const SizedBox(height: 400),
          ]),
        ),
      ),
    ]);

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
      // the boundary sits ABOVE the Navigator, so the sheet / dialog (an overlay route) is in the picture
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: SafeArea(child: child))),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [sheet] null → the page itself; else the page with the sheet opened over it (bottom sheet / dialog).
Future<void> _render(WidgetTester tester, String name, {bool live = false, Widget Function()? sheet}) async {
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
          await tester.pumpWidget(_host(_homeBehind(live: live), dark: dark));
          await _frames(tester, 3);
          if (sheet != null) {
            final ctx = tester.element(find.byType(GoLiveButton));
            showGoLiveSheet(ctx, sheet());
          }
          await _frames(tester);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/go_live_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

GoLiveSheet _sheet(List<GoLiveSession> rows, {int course = 3}) =>
    GoLiveSheet(courses: goLiveCourseOrder(_courses()), initialCourseId: course, api: _Api(rows), now: _now);

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  testWidgets('header', (tester) async {
    await _render(tester, 'header');
    await _render(tester, 'header_live', live: true);
  });

  testWidgets('sheet scheduled', (tester) async {
    await _render(tester, 'scheduled',
        sheet: () => _sheet([
              GoLiveSession(id: 9, name: tr('المحاضرة ٧: الشبكات العصبية', 'Lecture 7: neural networks'), startsAt: _now.add(const Duration(minutes: 12)), minutes: 90),
            ]));
  });

  testWidgets('sheet new', (tester) async {
    await _render(tester, 'new', sheet: () => _sheet(const []));
  });

  testWidgets('sheet live', (tester) async {
    await _render(tester, 'live',
        sheet: () => _sheet([
              GoLiveSession(id: 9, name: tr('المحاضرة ٧: الشبكات العصبية', 'Lecture 7: neural networks'), startsAt: _now.subtract(const Duration(minutes: 25)), minutes: 90, live: true),
            ]));
  });
}
