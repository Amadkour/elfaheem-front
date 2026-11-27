// Review renders of the student's live and attendance screens (Stu1Learn prejoin / attend / checkin, SubjectProfile
// live + fullscreen live): 390x844 and 1360x900, ar (+ en for the main states), CAST demo data. Not a CI suite;
// compare by eye with D:/platform/redesign-ref/ref/student/05{0..4}_*.png and subject/0{09,10,25,26}_*.png.
//
//   flutter test test/visual/redesign/sb/live_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_attend_view.dart';
import 'package:flutter_education_app/features/attendance/student_ui/student_checkin_view.dart';
import 'package:flutter_education_app/features/live/room/prejoin_student.dart';
import 'package:flutter_education_app/features/live/room/student/student_live_parts.dart';
import 'package:flutter_education_app/features/live/room/student/student_room_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _prejoin() => StudentPreJoinLayout(
      lessonTitle: _t('الدوال الأسية', 'Exponential functions'),
      teacherName: _t('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      userName: _t('فيصل العنزي', 'Faisal Alanazi'),
      classLine: _t('الرياضيات، حصة مباشرة ٥٠ دقيقة', 'Maths, a 50-minute live class'),
      startedMinutes: 12,
      micOn: true,
      camOn: false,
      micLevel: 0.7,
      onToggleMic: () {},
      onToggleCam: () {},
      busy: false,
      onJoin: () {},
      onBack: () {},
      mics: const [('a', 'Built-in microphone'), ('b', 'Headset')],
      cams: const [('c', 'Front camera'), ('d', 'USB camera')],
      onMicChanged: (_) {},
      onCamChanged: (_) {},
    );

/// A stand-in for the teacher's board on the stage (the real room draws the board / share / camera here).
class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.cardBg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpace.xxxl + AppSpace.lg),
            Text(_t('الدوال الأسية   ص = ٢^س', 'Exponential functions   y = 2^x'),
                style: AppType.headline(context).copyWith(color: c.kit.warmTone.ink)),
            const Spacer(),
            Text(_t('د(٣) = ٢^٣ = ٨', 'f(3) = 2^3 = 8'), style: AppType.section(context)),
          ],
        ),
      ),
    );
  }
}

/// The teacher's small camera tile on the stage (room.dart's presenter cam).
class _TeacherCam extends StatelessWidget {
  const _TeacherCam();

  @override
  Widget build(BuildContext context) => PositionedDirectional(
        top: AppSpace.sm,
        end: AppSpace.sm,
        child: Container(
          width: AppDashSize.courseTile * 0.6,
          height: AppDashSize.avatar * 1.1,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: context.colors.kit.ok.color, width: AppBorder.focus * 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.tile - AppBorder.focus),
            child: AppAreaScope(
              area: AppArea.learn,
              child: Builder(
                builder: (context) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppAreaScope.of(context).a, AppAreaScope.of(context).b]),
                  ),
                  child: Center(
                    child: Text(_t('أ. ماجد الشهري', 'Mr Majed'),
                        style: AppType.label(context).copyWith(color: context.colors.onHero, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

Widget _room({bool full = false}) => StudentRoomView(
      lessonTitle: _t('حصة الرياضيات، مباشر', 'Maths class, live'),
      teacherName: _t('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      liveFor: '05:12',
      stage: const _Board(),
      stageOverlays: const [_TeacherCam()],
      micOn: false,
      micAllowed: false,
      handUp: false,
      fullScreen: full,
      onToggleFullScreen: () {},
      onToggleMic: () {},
      onToggleHand: () {},
      onAsk: () {},
      onLeave: () {},
      onMinimize: () {},
    );

Widget _attend() => StudentAttendView(
      kicker: _t('الرياضيات، ثاني ثانوي', 'Maths, Grade 11'),
      open: StudentAttendOpen(
        lesson: _t('الدوال الأسية', 'Exponential functions'),
        teacherName: _t('أ. ماجد', 'Mr Majed'),
        minutesLeft: 8,
      ),
      onCheckIn: () {},
      onBack: () {},
      rows: [
        StudentAttendRow(lesson: _t('مراجعة الوحدة الأولى', 'Unit 1 review'), at: DateTime.utc(2026, 11, 22, 16, 30), status: StudentAttendStatus.present),
        StudentAttendRow(lesson: _t('الدوال العكسية', 'Inverse functions'), at: DateTime.utc(2026, 11, 19, 16, 30), status: StudentAttendStatus.present),
        StudentAttendRow(lesson: _t('تحويلات الدوال', 'Transformations'), at: DateTime.utc(2026, 11, 15, 16, 30), status: StudentAttendStatus.late),
        StudentAttendRow(lesson: _t('المجال والمدى', 'Domain and range'), at: DateTime.utc(2026, 11, 12, 16, 30), status: StudentAttendStatus.absent),
        StudentAttendRow(lesson: _t('مدخل إلى الدوال', 'Intro to functions'), at: DateTime.utc(2026, 11, 8, 16, 30), status: StudentAttendStatus.present),
      ],
    );

/// The sheet over the attend page, as on a phone (bottom) or in the wide dialog.
Widget _sheet(StudentCheckInPhase phase) => AppAreaScope(
      area: AppArea.learn,
      child: Builder(builder: (context) {
        final phone = MediaQuery.sizeOf(context).width < 700;
        final sheet = Material(
          color: context.colors.cardBg,
          borderRadius: phone
              ? const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))
              : BorderRadius.circular(AppRadius.sheet),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: StudentCheckInView(phase: phase, onClose: () {}, doneAt: _t('٧:٣٢ م', '7:32 PM')),
          ),
        );
        return Stack(children: [
          Positioned.fill(child: _attend()),
          Positioned.fill(child: ColoredBox(color: appScrimColor(context))),
          Align(
            alignment: phone ? Alignment.bottomCenter : Alignment.center,
            child: SizedBox(width: phone ? double.infinity : AppWidth.form.max, child: sheet),
          ),
        ]);
      }),
    );

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('prejoin', (t) async {
    await kitRender(t, 'sb_live_prejoin', _prejoin, storage: storage, modes: const [false], grow: false);
  });

  testWidgets('room', (t) async {
    await kitRender(t, 'sb_live_room', _room, storage: storage, modes: const [false], grow: false);
  });

  testWidgets('room full screen', (t) async {
    await kitRender(t, 'sb_live_room_full', () => _room(full: true),
        storage: storage, modes: const [false], langs: const ['ar'], grow: false);
  });

  testWidgets('attend', (t) async {
    await kitRender(t, 'sb_att_attend', _attend, storage: storage, modes: const [false]);
  });

  testWidgets('check-in running', (t) async {
    await kitRender(t, 'sb_att_checkin', () => _sheet(StudentCheckInPhase.running),
        storage: storage, modes: const [false], langs: const ['ar'], grow: false);
  });

  testWidgets('check-in done', (t) async {
    await kitRender(t, 'sb_att_done', () => _sheet(StudentCheckInPhase.done),
        storage: storage, modes: const [false], grow: false);
  });

  test('initial skips the title', () => expect(liveInitial('أ. ماجد الشهري'), 'م'));
}
