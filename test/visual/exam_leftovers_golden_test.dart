// Visual review renders of round 3's leftovers of the paper-exam e2e, compared by eye like the other test/visual
// files (NOT a CI suite). The PNGs go OUTSIDE the repo:
//
//   LO_RENDER_DIR=<dir> flutter test test/visual/exam_leftovers_golden_test.dart --update-goldens [--plain-name hub]
//
// → <dir>/lo_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900
//   results   the paper-exam results page scrolled to its grades, with the assistant's docked tab where the host puts
//             it (its face now stays in the gutter: the score / percent are not under it)
//   exams     the student's course exams: one opening later ("Opens Thu 5 Nov, …"), one open, one with every attempt
//             used, one on paper — plus the tab
//   hub       the teacher's exam hub: the third tile counts Questions (legacy + engine) — plus the tab
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/exam_engine/engine_exams_section.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_page.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_hub_screen.dart';
import 'package:flutter_education_app/utils/live_events.dart';
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
final _dir = (Platform.environment['LO_RENDER_DIR'] ?? '${Directory.systemTemp.path}/lo_renders').replaceAll('\\', '/');

Map<String, dynamic> _p(String name) =>
    Map<String, dynamic>.from((jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map)['payload'] as Map);

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

/// The docked tab where AppAssistantHost puts it on a window without a role shell (its default spot).
Widget _withTab(BuildContext context, Widget page) {
  final mq = MediaQuery.of(context);
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final band = appAssistantBand(mq.size, mq.padding, topClear: kToolbarHeight, bottomClear: appAssistantBottomClear);
  final rest = AppAssistantSpot.fallback(rtl: rtl, wide: mq.size.width >= 700).toOffset(mq.size, mq.padding, band);
  final left = rest.dx + appAssistantBubbleSize / 2 < mq.size.width / 2;
  return Stack(children: [
    page,
    Positioned(
      left: appAssistantDockX(mq.size, mq.padding, left: left),
      top: rest.dy - (appAssistantTabHeight - appAssistantBubbleSize) / 2,
      child: AppAssistantEdgeTab(onLeftSide: left, onTap: () {}),
    ),
  ]);
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
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Builder(builder: (context) => _withTab(context, w!)),
        ),
      ),
      home: child,
    ),
  );
}

Map<String, dynamic> _exam(int id, String title, Map<String, dynamic> extra) => {
      'id': id, 'title': title, 'status': 'published', 'duration_minutes': 30, 'attempts_used': 0, 'attempts_allowed': 1,
      'can_start': false, 'paper_only': false, 'open_attempt_id': null, 'results': const [], 'start_block': null, 'opens_at': null,
      ...extra,
    };

final _routes = <String, FakeHandler>{
  'GET /api/v1/exam/exams/1/omr/results': (_) => _p('bubble_results'),
  'GET /api/v1/exam/student/exams': (_) => {
        'items': [
          _exam(1, 'CS101 Quiz 1 (online)', {
            'starts_at': '2026-11-05T09:00:00', 'ends_at': '2026-11-05T11:00:00', 'opens_at': '2026-11-05T09:00:00',
            'start_block': {'code': 'exam_not_started', 'message': 'لم يبدأ الاختبار بعد', 'message_en': 'The exam has not started yet.',
                            'opens_at': '2026-11-05T09:00:00'},
          }),
          _exam(2, 'CS101 Online now (R3)', {'can_start': true}),
          _exam(3, 'CS101 Warm-up quiz', {
            'attempts_used': 1, 'start_block': {'code': 'no_attempts_left', 'message': 'استهلكت محاولاتك في هذا الاختبار'},
            'results': [{'visible': false}],
          }),
          _exam(4, 'CS101 Handwritten paper-only (B4)', {'paper_only': true, 'start_block': {'code': 'paper_exam', 'message': 'x'}}),
        ],
        'server_time': '2026-11-03T12:00:00',
      },
  'GET /api/v1/exam/exams': (_) => {
        'items': [
          {'id': 11, 'title': 'CS101 Online now (R3)', 'status': 'published', 'attempts': {'total': 1}, 'question_count': 5},
          {'id': 12, 'title': 'CS101 Bubble regression (R3)', 'status': 'published', 'attempts': {'total': 4}, 'question_count': 20},
          {'id': 13, 'title': 'CS101 Written paper-only (R3)', 'status': 'published', 'attempts': {'total': 2}, 'question_count': 3},
          {'id': 14, 'title': 'Draft: chapter 4 check', 'status': 'draft', 'attempts': {'total': 0}, 'question_count': 0},
        ],
      },
  'GET /api/v1/courses/1/exams/all': (_) => const [
        {'id': 9, 'name': 'Legacy quiz', 'course_id': 1, 'created_at': '2026-10-01T00:00:00', 'questions_count': 4, 'is_published': true},
      ],
  'GET /api/v1/courses/1/sessions': (_) => const {'items': <Object>[]},
};

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(_routes, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) await act(tester);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/lo_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    fake.uninstall();
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// Scrolls the page's list until its grade cards sit at the tab's height (the e2e phone shot was taken there).
Future<void> _toGrades(WidgetTester tester) async {
  final grade = find.text('Student 11');
  if (grade.evaluate().isEmpty) return;
  final list = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(list);
  final y = tester.getTopLeft(grade.first).dy;
  final target = tester.view.physicalSize.height * 0.62;
  state.position.jumpTo((state.position.pixels + y - target).clamp(0.0, state.position.maxScrollExtent));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('results', (t0) => _render(t0, 'results',
      () => OmrResultsPage(examId: 1, liveStream: _stream, liveBus: LiveEvents.instance), act: _toGrades));
  testWidgets('exams', (t0) => _render(t0, 'exams', () => Builder(
      builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('CS101')),
            body: const SingleChildScrollView(child: EngineExamsSection(courseId: 1)),
          ))));
  testWidgets('hub', (t0) => _render(t0, 'hub', () => const TeacherExamHubScreen(courseId: 1, courseTitle: 'Introduction to Programming')));
}
