// Visual review renders of the instructor's home area in the Warm Editorial theme, compared by eye like the other
// test/visual files (NOT a CI suite):
//
//   flutter test test/visual/teacher_home_golden_test.dart --update-goldens [--plain-name todo]
//
// → test/visual/goldens/teacher_area_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   home        the premium dashboard (D-631): the forest greeting hero + Go live (beside the Today card with the
//               day ribbon on desktop), shortcuts, live meeting, to-do, figures, course tiles, inbox over real
//               /me/home teacher to-do data
//   free        a day without sessions: no ribbon, Today folded (phone) / says so (desktop)
//   todo        the full to-do page over the real merged list (urgent = the peach block)
//   schedules   a course's weekly appointments: the sky week block and the cards
//   stats       the instructor profile's rating figures (the gold block + paper cards)
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeLiveRoom;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/teacher/home_screen.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_extra.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_screen.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_page.dart';
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

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/payloads/$name.json').readAsStringSync()) as Map<String, dynamic>;

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);
final _shot = GlobalKey();
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// 09:00 in Cairo (07:00 UTC).
final _now = DateTime.now().toUtc().copyWith(hour: 7, minute: 0, second: 0, millisecond: 0, microsecond: 0);

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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 16]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _renderAll(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [_phone, _desktop]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            final h = math.min(5000.0, tester.view.physicalSize.height + extra);
            if (h <= tester.view.physicalSize.height) break;
            tester.view.physicalSize = Size(size.width, h);
            await _frames(tester, 6);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/teacher_area_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

// ── data ────────────────────────────────────────────────────────────────────

ScheduleSession _session(int id, String name, String start, String end, {bool ongoing = false, int? untilStart, int inDays = 0}) =>
    ScheduleSession(
      scheduleId: id,
      courseId: id,
      courseName: name,
      day: 'wednesday',
      dayLabel: 'wednesday',
      startTime: start,
      endTime: end,
      durationMinutes: 90,
      isToday: inDays == 0,
      isOngoing: ongoing,
      scheduledDate: _now.add(Duration(days: inDays)),
      minutesUntilStart: ongoing ? null : untilStart,
      minutesUntilEnd: ongoing ? 40 : null,
      maxStudents: 120,
      dayLabelStr: 'wednesday',
    );

List<ScheduleSession> _schedule({bool free = false}) => free
    ? [
        _session(1, tr('تراكيب البيانات', 'Data structures'), '06:00', '07:30', inDays: 1),
        _session(3, tr('الذكاء الاصطناعي', 'Artificial intelligence'), '09:00', '10:30', inDays: 2),
      ]
    : [
        _session(1, tr('تراكيب البيانات', 'Data structures'), '05:00', '06:20'),
        _session(2, tr('معمل الشبكات', 'Networks lab'), '06:10', '07:40', ongoing: true),
        _session(3, tr('الذكاء الاصطناعي', 'Artificial intelligence'), '10:00', '11:30', untilStart: 180),
      ];

TeacherHomeExtra _extra() => TeacherHomeExtra.fromJson({
      'pending': {'attendance_missing': 2, 'grading': 18, 'materials_missing': 1, 'enrollment_requests': 7},
      'teaching_courses': 6,
      'earnings': {'month': 18450.0, 'pending_payout': 2500},
      'todo': _fixture('me_home_teacher_todo'),
      'inbox_preview': [
        {'key': 'f1', 'kind': 'form', 'segment': 'todo', 'title': tr('اعتماد درجات أعمال السنة', 'Approve coursework marks'), 'subtitle': tr('قسم علوم الحاسب', 'CS department'), 'urgency': 'due_soon', 'mandatory': true},
      ],
      'notifications_unread': 5,
    });

List<TeacherCourse> _courses() => [
      for (final (id, ar, en, students, published) in [
        (1, 'تراكيب البيانات', 'Data structures', 420, true),
        (2, 'معمل الشبكات', 'Networks lab', 380, true),
        (3, 'الذكاء الاصطناعي', 'Artificial intelligence', 610, true),
        (4, 'نظم التشغيل', 'Operating systems', 290, true),
        (6, 'تعلم الآلة المتقدم', 'Advanced machine learning', 0, false),
      ])
        TeacherCourse(
          id: id,
          imageUrl: '',
          totalHours: 0,
          type: 'live',
          progress: 0,
          expectedHours: 0,
          isPublished: published,
          studentsCount: students,
          sessionsCount: 24,
          titleAr: ar,
          titleEn: en,
        ),
    ];

List<MeLiveRoom> _live() => [
      MeLiveRoom(
        kind: 'meeting',
        id: 9,
        title: tr('مجلس قسم علوم الحاسب', 'Computer science department council'),
        meetingId: 9,
        orgId: 4,
        hostName: tr('أ.د. هاني فوزي', 'Prof. Hany Fawzy'),
        startedAt: _now.subtract(const Duration(minutes: 4, seconds: 5)),
      ),
    ];

Widget _home({bool free = false}) {
  final schedule = _schedule(free: free);
  return SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kHomeWideMax),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TeacherHomeBody(
            liveNow: free ? const [] : _live(),
            now: _now,
            loading: false,
            stats: const TeacherStats(totalStudents: 1840, totalCourses: 6, overallRating: 4.8),
            schedule: schedule,
            pending: const {'attendance_missing': 2, 'grading': 18, 'materials_missing': 1, 'enrollment_requests': 7},
            courses: _courses(),
            extra: _extra(),
            onTab: (_) {},
            onOpenCourse: (_) {},
            onOpenCourseId: (_) {},
            onNewCourse: () {},
            onOpenEarnings: () {},
            onOpenInbox: () {},
            showFeeds: false,
          ),
        ]),
      ),
    ),
  );
}

Widget _todo() {
  final core = TodoList.fromJson(_fixture('teacher_todo'));
  final engine = [for (final x in _fixture('teacher_todo_engine')['items'] as List) TodoItem.fromJson(x)!];
  return TeacherTodoView(
    list: mergeTodo(core, engine),
    updatedAt: DateTime.now(),
    onRefresh: () async {},
    onOpen: (_) {},
    onMenu: (_, _) {},
    onRestore: (_) {},
    onBack: () {},
  );
}

Widget _schedules() => TeacherSchedulesView(
      schedules: const [
        CourseSchedule(id: 1, courseId: 3, day: 'sunday', startTime: '08:00', endTime: '09:30'),
        CourseSchedule(id: 2, courseId: 3, day: 'tuesday', startTime: '10:00', endTime: '11:30'),
        CourseSchedule(id: 3, courseId: 3, day: 'tuesday', startTime: '14:00', endTime: '15:00'),
        CourseSchedule(id: 4, courseId: 3, day: 'thursday', startTime: '12:30', endTime: '14:00'),
      ],
      onAdd: () {},
      onDelete: (_) {},
    );

Widget _stats() => const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpace.lg),
      child: StatsRow(
        stats: TeacherStats(totalStudents: 1840, totalCourses: 6, overallRating: 4.8, doctorRating: 4.9, courseRating: 4.7, materialRating: 4.6),
        isFull: true,
      ),
    );

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    homeAttentionBadge = (_, child) => child;
    AppModeController.applyContext = (_) {};
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = [];
    AppModeController.instance.debugSet({
      'items': [
        {
          'organization': {'id': 4, 'name': 'جامعة النيل', 'name_en': 'Nile University', 'slug': 'nile'},
          'roles': ['teacher'],
          'manage': null,
          'todo': {'total': 4},
          'approvals': {'total': 6},
        },
      ],
      'default_org_id': 4,
      'pending_total': 10,
    }, mode: AppMode.individual);
  });

  testWidgets('home', (tester) async {
    HomeFolds.instance.debugReset();
    await _renderAll(tester, 'home', _home);
  });

  testWidgets('free', (tester) async {
    HomeFolds.instance.debugReset();
    await _renderAll(tester, 'free', () => _home(free: true));
  });

  testWidgets('todo', (tester) async {
    await _renderAll(tester, 'todo', _todo);
  });

  testWidgets('schedules', (tester) async {
    await _renderAll(tester, 'schedules', _schedules);
  });

  testWidgets('stats', (tester) async {
    await _renderAll(tester, 'stats', _stats);
  });
}
