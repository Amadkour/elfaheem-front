// The teacher's pieces of the shared course page, the add / edit session sheet and a course's enrolled students at
// 320×640 and 1400×900, ar / en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/teacher/component/add_item_dialog.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/student/models.dart' show TeacherSessionItem;
import 'package:flutter_education_app/features/teacher/sessions/components/session_form_sheet.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/teacher_course_parts.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين — A complete, very long introduction';

TeacherCourse _course({bool published = true, bool rich = true, String type = 'live'}) => TeacherCourse.fromJson({
  'id': 7,
  'image_url': '',
  'name_ar': _long,
  'name_en': _long,
  if (rich) 'description_ar': '$_long $_long $_long',
  if (rich) 'description_en': '$_long $_long $_long',
  'students_count': 12480,
  'sessions_count': 148,
  'total_hours': 42.5,
  'expected_hours': rich ? 60.0 : 0.0,
  'price': 1500,
  'final_price': 999.0,
  'discount_active': true,
  'discount_percentage': 33.0,
  'type': type,
  'is_published': published,
  if (rich) ...{
    'schedules': [
      for (final d in ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday'])
        {'id': 1, 'day': d, 'start_time': '09:00', 'end_time': '11:30'},
    ],
    'certificates': [
      {'id': 3, 'title': 'شهادة إتمام المقرر مع مرتبة الشرف — Certificate of completion with honours', 'description': _long},
      {'id': 4, 'title': 'شهادة حضور'},
    ],
    'tools': [
      {'id': 4, 'title': 'Visual Studio Code with a very long tool name that has to wrap on a phone', 'description': _long},
    ],
    'prerequisites': [
      {'id': 5, 'title': 'أساسيات البرمجة', 'description': _long},
    ],
  },
});

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('course form: the add-an-item dialog (kit buttons in both languages, a long hint)', (t) async {
    final ctrl = TextEditingController(text: _long);
    addTearDown(ctrl.dispose);
    await expectNoLayoutErrors(t, () => AddItemPanel(hint: _long, ctrl: ctrl),
        act: (t) async => expect(find.byKey(const ValueKey('add_item.add')), findsOneWidget));
  });

  testWidgets('details tab: everything, long Arabic data', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: TeacherCourseDetails(
          course: _course(),
          rating: const SizedBox(height: 40),
          onManageSchedule: () {},
          onManageCertificate: (_) {},
        ),
      ),
    );
  });

  testWidgets('details tab: empty live course asks for a schedule', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(child: TeacherCourseDetails(course: _course(rich: false), onManageSchedule: () {})),
      act: (t) async => expect(find.byIcon(Icons.add_rounded), findsOneWidget),
    );
  });

  testWidgets('details tab: empty recorded course says there is nothing yet', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(child: TeacherCourseDetails(course: _course(rich: false, type: 'recorded'))),
    );
  });

  testWidgets('sessions header (with and without sessions) and the empty state', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(
          children: [
            TeacherSessionsHeader(count: 148, onAdd: () {}),
            TeacherSessionsHeader(count: 0, onAdd: () {}),
            Padding(
              padding: const EdgeInsets.all(kCourseGutter),
              child: TeacherSessionsEmpty(onAdd: () {}),
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('session sheet: edit a live session, details open (date, record switch, numbers)', (t) async {
    final existing = TeacherSessionItem.fromJson({
      'id': 41,
      'course_id': 7,
      'name': _long,
      'description': '$_long $_long',
      'type': 'live',
      'scheduled_at': '2026-11-20T15:00:00',
      'duration_minutes': 90,
    });
    await expectNoLayoutErrors(t, () {
      final p = TeacherCourseScreenProvider(initialCourse: _course())..openMoreDetailsForAddSession = true;
      return ChangeNotifierProvider.value(value: p, child: SessionFormSheet(provider: p, existing: existing));
    });
  });

  testWidgets('session sheet: a new session, details closed', (t) async {
    await expectNoLayoutErrors(t, () {
      final p = TeacherCourseScreenProvider(initialCourse: _course());
      return ChangeNotifierProvider.value(value: p, child: SessionFormSheet(provider: p));
    });
  });

  testWidgets('enrolled students: hero block, search, cards (list and grid), long names', (t) async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final api = FakeApi({
      'GET /api/v1/courses/7/students': (o) => {
            'items': [
              for (var i = 0; i < 6; i++)
                {
                  'id': 100 + i,
                  'name': i.isEven ? _long : 'Omar',
                  'gmail': 'a.very.long.email.address.$i@example-university.edu.eg',
                  if (i.isEven) 'username': 'a_rather_long_username_$i',
                  'enrolled_at': '2026-10-0${i + 1}T10:00:00',
                  'status': 'active',
                  'progress_percentage': i * 20.0,
                },
            ],
            'total': 12480,
            'avg_progress': 57.0,
            'completed_count': 1999,
          },
    }, latency: Duration.zero)
      ..install();
    addTearDown(api.uninstall);
    await expectNoLayoutErrors(
      t,
      // .value: the provider outlives each pumped variant (a fetch may still be in flight)
      () => ChangeNotifierProvider.value(value: EnrolledStudentsProvider(), child: EnrolledStudentsScreen(course: _course())),
      frames: 6,
    );
    await t.pump(const Duration(seconds: 30));
  });
}
