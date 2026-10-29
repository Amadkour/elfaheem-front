// VISUAL review renders of the one schedule page (D-085) with a realistic student week: org classes with one-date
// changes (online · substitute · cancelled), a lab, an exam, a live course session, a personal course's weekly
// appointment, meetings (an invitation to answer, an online one about to start), an exam-window pause — at 390x844
// and 1440x900, ar / en, light / dark, into test/visual/goldens/schedule_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/schedule_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_page.dart';
import 'package:flutter_education_app/features/shared/calendar/schedule_store.dart';
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

String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Thursday 29 October 2026, 9:50 on the wall clock.
DateTime _wall(int day, int h, [int m = 0]) => DateTime(2026, 10, 29 + day, h, m);
DateTime get _now => AppTime.fromZone(_wall(0, 9, 50)).toUtc();
String _iso(DateTime wall) => AppTime.fromZone(wall).toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> get _org => {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'};

Map<String, dynamic> _ev(String id, String source, DateTime s, DateTime e, String title,
        {String? sub, String? loc, String? kind, int? meeting, String? status, bool owner = false, String? mode, Map<String, dynamic>? change, bool cancelled = false, int? course, bool org = true}) =>
    {
      'id': id,
      'source': source,
      'title': title,
      'subtitle': sub,
      'starts_at': _iso(s),
      'ends_at': _iso(e),
      'org_id': org ? 4 : null,
      'org': org ? _org : null,
      'location': loc,
      'mode': mode,
      'kind': kind,
      'meeting_id': meeting,
      'my_status': owner ? 'owner' : status,
      'is_owner': owner,
      'editable': owner,
      'course_id': course,
      'change': ?change,
      if (cancelled) 'cancelled': true,
    };

List<Map<String, dynamic>> _week() {
  final dr = tr('د. أحمد سالم', 'Dr. Ahmed Salem');
  final out = <Map<String, dynamic>>[];
  // weekly classes, Saturday 24 Oct → Saturday 21 Nov
  for (var d = -5; d < 24; d++) {
    final day = _wall(d, 0);
    final wd = day.weekday;
    if (wd == DateTime.friday) continue;
    final paused = d >= 9 && d <= 13; // the midterm window
    if (paused) continue;
    if (wd == DateTime.thursday || wd == DateTime.sunday || wd == DateTime.tuesday) {
      out.add(_ev('slot:ds:$d', 'timetable', _wall(d, 8, 30), _wall(d, 9, 45), tr('هياكل البيانات', 'Data structures'),
          sub: dr, loc: tr('قاعة 204', 'Hall 204'), kind: 'lecture', course: 11));
      out.add(_ev('slot:net:$d', 'timetable', _wall(d, 11), _wall(d, 12, 30), tr('معمل الشبكات', 'Networks lab'),
          sub: tr('م. سارة علي', 'Eng. Sara Ali'), loc: tr('معمل 3', 'Lab 3'), kind: 'lab', course: 12,
          change: d == 0 ? {'id': 71, 'mode': 'online', 'online_url': 'https://meet.example/net', 'cancelled': false, 'substitute': false, 'my_response': null, 'can_respond': true, 'can_edit': false, 'responses': {'accept': 18, 'reject': 2}} : null,
          mode: d == 0 ? 'online' : null));
    }
    if (wd == DateTime.saturday || wd == DateTime.monday || wd == DateTime.wednesday) {
      out.add(_ev('slot:os:$d', 'timetable', _wall(d, 10), _wall(d, 11, 30), tr('نظم التشغيل', 'Operating systems'),
          sub: d == 2 ? tr('د. منى فؤاد', 'Dr. Mona Fouad') : dr, loc: tr('قاعة 112', 'Hall 112'), kind: 'lecture', course: 13,
          change: d == 2 ? {'id': 72, 'mode': null, 'cancelled': false, 'substitute': true, 'my_response': null, 'can_respond': true, 'can_edit': false, 'responses': {'accept': 0, 'reject': 0}} : null));
      out.add(_ev('slot:ai:$d', 'timetable', _wall(d, 13), _wall(d, 14, 30), tr('الذكاء الاصطناعي', 'Artificial intelligence'),
          sub: dr, loc: tr('قاعة 301', 'Hall 301'), kind: 'lecture', course: 14,
          cancelled: d == 4,
          change: d == 4 ? {'id': 73, 'mode': null, 'cancelled': true, 'substitute': false, 'my_response': null, 'can_respond': true, 'can_edit': false, 'responses': {'accept': 0, 'reject': 0}} : null));
    }
  }
  out.addAll([
    _ev('exam:1', 'exam', _wall(0, 13), _wall(0, 14), tr('اختبار: الإحصاء', 'Quiz: Statistics'),
        sub: tr('اختبارات قصيرة', 'Short quizzes'), loc: tr('قاعة 301', 'Hall 301'), kind: 'quiz', course: 15),
    _ev('session:501', 'course_session', _wall(0, 9, 30), _wall(0, 10, 30), tr('مراجعة الوحدة الثالثة', 'Unit 3 review'),
        sub: tr('أساسيات بايثون', 'Python fundamentals'), course: 21, mode: 'online', org: false),
    _ev('meeting:31', 'meeting', _wall(0, 16), _wall(0, 17), tr('لقاء المرشد الأكاديمي', 'Advisor meeting'),
        loc: tr('مكتب 12', 'Office 12'), meeting: 31, status: 'pending', mode: 'offline'),
    _ev('meeting:32', 'meeting', _wall(1, 10), _wall(1, 11), tr('فريق مشروع التخرج', 'Graduation project team'),
        meeting: 32, status: 'accepted', mode: 'online'),
    _ev('meeting:33', 'meeting', _wall(2, 18), _wall(2, 19), tr('مذاكرة جماعية', 'Study group'),
        meeting: 33, owner: true, mode: 'online', kind: 'private', org: false),
    _ev('exam:2', 'exam', _wall(10, 9), _wall(10, 11), tr('نظم التشغيل', 'Operating systems'),
        sub: tr('امتحانات منتصف الفصل', 'Midterm exams'), loc: tr('مدرج A', 'Hall A'), kind: 'midterm', course: 13),
    _ev('exam:3', 'exam', _wall(12, 9), _wall(12, 11), tr('هياكل البيانات', 'Data structures'),
        sub: tr('امتحانات منتصف الفصل', 'Midterm exams'), loc: tr('مدرج B', 'Hall B'), kind: 'midterm', course: 11),
  ]);
  return out;
}

class _Api extends RemoteCalendarApi {
  const _Api();

  @override
  Future<dynamic> feed(String start, String end, {int? orgId, int? deptId, bool detail = false}) async => {
        'items': _week(),
        'pending_invites': 1,
        'pauses': [
          {
            'exam_schedule_id': 9,
            'name': tr('امتحانات منتصف الفصل', 'Midterm exams'),
            'kind': 'midterm',
            'start_date': '2026-11-07',
            'end_date': '2026-11-11',
            'org_id': 4,
            'org': _org,
          },
        ],
      };
}

Future<dynamic> _weekly(String path) async => {
      'all_courses': [
        {
          'course_id': 22,
          'course_name': tr('اللغة الإنجليزية للأعمال', 'Business English'),
          'schedules': [
            {'schedule_id': 5, 'course_id': 22, 'course_name': tr('اللغة الإنجليزية للأعمال', 'Business English'), 'day': 'thursday', 'start_time': '19:00', 'end_time': '20:00'},
            {'schedule_id': 6, 'course_id': 22, 'course_name': tr('اللغة الإنجليزية للأعمال', 'Business English'), 'day': 'saturday', 'start_time': '19:00', 'end_time': '20:00'},
          ],
        },
      ],
    };

final _shot = GlobalKey();

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

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, CalView? Function(Size size) view, {bool grow = true, List<Size> sizes = const [Size(390, 844), Size(1440, 900)]}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(
            SchedulePage(
              key: UniqueKey(),
              api: const _Api(),
              store: CalendarStore(),
              now: _now,
              liveKeys: const {'session:501'},
              weeklyGet: _weekly,
              role: 'student',
              initialView: view(size),
            ),
            dark: dark,
          ));
          final prevOnError = FlutterError.onError;
          FlutterError.onError = (d) {
            // the layout errors' details (takeException keeps only the summary)
            debugPrint(d.toString().split('\n').where((l) => l.contains('creator') || l.contains('lib/') || l.contains('overflowed')).take(8).join('\n'));
            prevOnError?.call(d);
          };
          await _frames(tester);
          FlutterError.onError = prevOnError;
          if (grow && size.width < 700) {
            for (var i = 0; i < 4; i++) {
              var extra = 0.0;
              for (final e in find.byType(Scrollable).evaluate()) {
                final s = (e as StatefulElement).state as ScrollableState;
                if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                  extra = math.max(extra, s.position.maxScrollExtent);
                }
              }
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(3200, tester.view.physicalSize.height + extra));
              await _frames(tester, 6);
            }
          }
          final ex = tester.takeException();
          if (ex != null) debugPrint('[$name $size $lang ${dark ? 'dark' : 'light'}] ${ex is FlutterError ? ex.toStringDeep() : ex}');
          expect(ex, isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
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
  setUp(() {
    AppConfig.disableList = [];
  });

  testWidgets('schedule: default view (phone agenda · desktop week)', (tester) async {
    await _render(tester, 'schedule_default', (_) => null, grow: true);
  });

  testWidgets('schedule: day', (tester) async {
    await _render(tester, 'schedule_day', (_) => CalView.day, grow: false);
  });

  testWidgets('schedule: month', (tester) async {
    await _render(tester, 'schedule_month', (_) => CalView.month, grow: true);
  });

  testWidgets('schedule: agenda on desktop · week on phone', (tester) async {
    await _render(tester, 'schedule_alt', (s) => s.width < 700 ? CalView.week : CalView.agenda, grow: false);
  });
}
