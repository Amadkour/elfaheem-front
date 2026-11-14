// VISUAL review renders of the teacher's session pages outside the live room: a course's enrolled students (hero
// progress block, search, cards), the add / edit session sheet (details open, a live session) and the guest link
// sheet (a link with a PIN, the QR, the joins list), at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/teacher_sessions_*.png. Not a CI suite; compared by eye. The course page's own teacher pieces
// render in course_space_golden_test.dart ("course teacher …").
//
//   flutter test test/visual/teacher_sessions_golden_test.dart --update-goldens [--plain-name students]
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
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp;
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/student/models.dart' show TeacherSessionItem;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/guest_link_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/session_form_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {bool grow = true}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          AppCountUp.resetMemory();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          for (var i = 0; grow && i < 4; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(5000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/teacher_sessions_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String().replaceAll('Z', '');

const _names = [
  'سارة محمود عبد الرحمن',
  'Omar Khaled',
  'مريم أحمد السيد',
  'Youssef Ibrahim El-Masry',
  'ليلى حسن',
  'Ahmed Tarek',
  'نور الهدى مصطفى',
  'Karim Adel',
];

TeacherCourse _course() => TeacherCourse.fromJson({
      'id': 7,
      'image_url': '',
      'name_ar': 'أساسيات الذكاء الاصطناعي بلغة بايثون',
      'name_en': 'AI Foundations with Python',
      'students_count': 128,
      'sessions_count': 12,
      'total_hours': 18.0,
      'expected_hours': 24.0,
      'price': 1200,
      'final_price': 750.0,
      'type': 'live',
      'is_published': true,
      'certificates': [
        {'id': 3, 'title': 'Certificate of completion'},
      ],
    });

FakeApi _students() => FakeApi({
      'GET /api/v1/courses/7/students': (o) => {
            'items': [
              for (final (i, n) in _names.indexed)
                {
                  'id': 100 + i,
                  'name': n,
                  'gmail': 'student${i + 1}@example.com',
                  if (i.isEven) 'username': 'learner_${i + 1}',
                  'enrolled_at': _iso(Duration(days: 10 + 3 * i)),
                  'status': 'active',
                  'progress_percentage': [96.0, 82.0, 64.0, 51.0, 38.0, 22.0, 100.0, 8.0][i],
                  'lessons_done': [23, 20, 15, 12, 9, 5, 24, 2][i],
                  'lessons_total': 24,
                  'last_active_at': i == 7 ? null : _iso(Duration(hours: [2, 20, 30, 50, 9 * 24, 13 * 24, 26 * 24, 0][i])),
                  'exam_avg': [91.0, 84.5, null, 72.0, 61.0, null, 88.0, null][i],
                  'state': ['active', 'active', 'active', 'active', 'low', 'low', 'completed', 'inactive'][i],
                  'at_risk': i == 4 || i == 5 || i == 7,
                  'risk': [
                    null, null, null, null,
                    {'code': 'no_activity', 'days': 9},
                    {'code': 'behind_pace', 'expected': 60.0, 'progress': 22.0},
                    null,
                    {'code': 'never_started', 'days': 31},
                  ][i],
                  'parent_count': i.isOdd ? 1 : 0,
                  'last_nudged_at': i == 5 ? _iso(const Duration(hours: 3)) : null,
                  'can_nudge': i != 5,
                },
            ],
            'total': 128,
            'avg_progress': 57.0,
            'completed_count': 19,
            'counts': {'all': 128, 'active': 74, 'low': 23, 'inactive': 9, 'completed': 19},
            'summary': {'enrolled': 128, 'active_week': 74, 'avg_progress': 57.0, 'at_risk': 23, 'completed': 19, 'low_nudgeable': 21, 'low_with_parent': 9},
            'rule': {'nudge_cooldown_hours': 24},
            'nudge_enabled': true,
          },
      'GET /api/v1/certificates/3/issuances': (o) => [
            {'student_id': 100},
            {'student_id': 106},
          ],
    }, latency: Duration.zero);

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  testWidgets('students', (t) async {
    final api = _students()..install();
    addTearDown(api.uninstall);
    await _render(
      t,
      'students',
      // .value: the provider outlives each variant (its fetch may still be in flight when the next one is pumped)
      () => ChangeNotifierProvider.value(
        value: EnrolledStudentsProvider(),
        child: EnrolledStudentsScreen(course: _course()),
      ),
      grow: false,
    );
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('session form', (t) async {
    final existing = TeacherSessionItem.fromJson({
      'id': 41,
      'course_id': 7,
      'name': 'Neural networks',
      'description': 'The lesson with its exercises and files',
      'type': 'live',
      'scheduled_at': '2026-11-20T15:00:00',
      'duration_minutes': 90,
    });
    await _render(t, 'form', () {
      final p = TeacherCourseScreenProvider(initialCourse: _course())..openMoreDetailsForAddSession = true;
      return ChangeNotifierProvider.value(
        value: p,
        child: Align(
          alignment: AlignmentDirectional.topEnd,
          child: SizedBox(width: 520, child: SessionFormSheet(provider: p, existing: existing)),
        ),
      );
    });
  });

  testWidgets('guest link', (t) async {
    const link = GuestLink(
      url: 'https://nextbrain.site/live/3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b',
      token: '3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e7d8f9a0b',
      canPublish: true,
      maxGuests: 25,
      guestsJoined: 7,
      hasPin: true,
    );
    await _render(t, 'guest_link', () {
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 560,
          child: GuestLinkBody(
            loading: false,
            busy: false,
            error: null,
            link: link,
            canPublish: true,
            maxGuestsController: TextEditingController(text: '25'),
            pinController: TextEditingController(),
            editing: false,
            showQr: true,
            joinsOpen: true,
            joins: [
              for (var i = 0; i < 3; i++)
                GuestJoinRecord(
                  identity: 'guest-$i',
                  name: i.isEven ? 'Mohamed Abdelrahman' : 'سارة محمود',
                  joinedAt: DateTime.utc(2026, 11, 10, 9, 30 + i),
                  ipMasked: '41.33.$i.xx',
                ),
            ],
            joinsTotal: 7,
            onRetry: () {},
            onCanPublishChanged: (_) {},
            onCreate: () {},
            onCopy: () {},
            onShare: () {},
            onToggleQr: () {},
            onToggleSettings: () {},
            onSaveSettings: () {},
            onRemovePin: () {},
            onRotate: () {},
            onRevoke: () {},
            onToggleJoins: () {},
            onRefreshJoins: () {},
          ),
        ),
      );
    });
  });
}
