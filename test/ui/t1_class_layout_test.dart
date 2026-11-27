// The redesigned T1 "Class" pieces (attendance: take panel, projector code and QR, QR card, manual register; the course
// page's announcements, team, archive; the path editor; the nudge composer) at 320x640 and 1400x900, ar / en,
// textScaler 1.3, over the CAST demo data of test/support/redesign/t1_class_fakes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/teacher_attendance_screen.dart';
import 'package:flutter_education_app/features/attendance/attendance_live_screen.dart';
import 'package:flutter_education_app/features/attendance/attendance_qr_card.dart';
import 'package:flutter_education_app/features/attendance/attendance_take_panel.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttView;
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_announcements.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_parts.dart';
import 'package:flutter_education_app/features/courses/course_profile/t1_class_parts.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_students_nudge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/redesign/t1_class_fakes.dart';
import 'layout_harness.dart';

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

List<LauncherSession> _lessons() => [
      for (var i = 1; i <= 6; i++)
        LauncherSession(id: i, number: i, name: i == 2 ? 'المتتابعات الهندسية والحسابية: أسئلة اختيار من متعدد مع الحل' : 'درس $i', date: DateTime.now().toUtc().add(Duration(days: i - 2))),
    ];

Widget _projector(AttView v, {AttProjectorState state = AttProjectorState.open, int present = 6}) => AttendanceProjectorView(
      view: v,
      state: state,
      usesCode: true,
      code: '482917',
      rotationSeconds: 45,
      secondsLeft: 18,
      closingLeft: 12,
      registrationLeft: const Duration(minutes: 7, seconds: 40),
      present: present,
      lesson: 'المتتابعات الهندسية والحسابية: أسئلة اختيار من متعدد مع الحل',
      onMinimize: () {},
      onClose: () {},
      onDone: () {},
    );

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('take panel: with and without the manual way, no lessons', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(AttendanceTakePanel(sessions: _lessons(), manualAvailable: true, onStart: (_, _) {})));
    await expectNoLayoutErrors(t, () => _scroll(AttendanceTakePanel(sessions: _lessons(), onStart: (_, _) {})));
    await expectNoLayoutErrors(t, () => _scroll(AttendanceTakePanel(sessions: const [], onStart: (_, _) {})));
  });

  testWidgets('take panel: today first and chosen, Start gives the lesson and the way', (t) async {
    LauncherSession? started;
    AttView? way;
    await t.pumpWidget(layoutHost(_scroll(AttendanceTakePanel(
        sessions: _lessons(),
        manualAvailable: true,
        nowUtc: DateTime.now().toUtc(),
        onStart: (s, v) {
          started = s;
          way = v;
        }))));
    await t.ensureVisible(find.byKey(const ValueKey('att.view.qr')));
    await t.tap(find.byKey(const ValueKey('att.view.qr')));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('att.start')));
    await t.tap(find.byKey(const ValueKey('att.start')));
    expect(started?.id, 2, reason: "today's lesson is chosen already");
    expect(way, AttView.qr);
  });

  testWidgets('projector: code, QR, closing, ended', (t) async {
    await expectNoLayoutErrors(t, () => _projector(AttView.code));
    await expectNoLayoutErrors(t, () => _projector(AttView.qr, present: 128));
    await expectNoLayoutErrors(t, () => _projector(AttView.code, state: AttProjectorState.closing));
    await expectNoLayoutErrors(t, () => _projector(AttView.qr, state: AttProjectorState.ended));
  });

  testWidgets('QR card: open and closed', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(const AttQrCard(code: '482917', secondsLeft: 12, registrationLeft: Duration(minutes: 7), lesson: 'المتتابعات الهندسية والحسابية: أسئلة اختيار من متعدد مع الحل')));
    await expectNoLayoutErrors(t, () => _scroll(const AttQrCard(code: '482917', secondsLeft: 0, registrationLeft: Duration.zero, open: false)));
  });

  testWidgets('manual register over FakeApi', (t) async {
    await t1SetUp(t1Api());
    await expectNoLayoutErrors(t, () => const TeacherAttendanceScreen(courseId: t1CourseId, courseTitle: t1CourseAr));
  });

  testWidgets('shared pieces: option card, note, count chip, toggle row', (t) async {
    await expectNoLayoutErrors(
        t,
        () => _scroll(Column(children: [
              ClOptionCard(title: 'قراءة بس ' * 6, subtitle: 'الطلاب يفتحون المحتوى للمراجعة بدون حضور ولا بث ' * 3, selected: true, onTap: () {}),
              const ClOptionCard(title: 'بطلب', selected: false, icon: Icons.lock_outline_rounded),
              ClNote(icon: Icons.info_outline_rounded, title: 'وش يقدر المعيد يسوي؟', text: 'كل صلاحياته تشتغل على سكاشنه بس. ' * 4),
              const ClCountChip('128'),
              ClToggleRow(title: 'أرسل إشعار للطلاب ' * 4, subtitle: 'يصل لكل الطلاب', value: true, onChanged: (_) {}),
            ])));
  });

  testWidgets('course page tabs: announcements, team, archive', (t) async {
    await t1SetUp(t1Api());
    final p = CourseProfile(t1ProfilePayload());
    await expectNoLayoutErrors(t, () => _scroll(CpAnnouncementsTab(profile: p, onChanged: () async {}, load: false)));
    await expectNoLayoutErrors(t, () => _scroll(CpTeamTab(profile: p, onChanged: () async {})));
    await expectNoLayoutErrors(t, () => _scroll(CpArchiveTab(profile: p, onChanged: () async {})));
  });

  testWidgets('path editor with this course drawn between before and after', (t) async {
    final rm = Roadmap.fromJson(t1Roadmap());
    await expectNoLayoutErrors(
        t,
        () => RoadmapEditorForm(
              draft: RoadmapDraft.of(rm, const []),
              course: rm.course,
              onAddNext: () {},
              onAddPrereq: () {},
              onChanged: () {},
            ));
  });

  testWidgets('nudge composer: the variable chips put the token at the cursor', (t) async {
    await t.pumpWidget(layoutHost(SingleChildScrollView(
        child: NudgeComposer(students: 2, withParent: 1, previewName: 'فيصل العنزي', courseName: t1CourseAr, onSend: (_, _) async => true))));
    await t.pump();
    await t.tap(find.text('{course}').first);
    await t.pump();
    expect(find.textContaining('{course}'), findsWidgets);
  });
}
