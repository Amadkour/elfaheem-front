// T1 course page: the teacher's hero, the setup checklist and the captions panel at 320x640 and 1400x900, ar / en,
// textScaler 1.3, with worst-case text.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart' show CourseSetupStep;
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/course_space/course_teacher_hero.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_education_app/features/sessions/material/material_guest_links_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'الرياضيات ٣ ثانوي، مجموعة أ مع شرح موسّع وتدريب مكثف على أسئلة التحصيلي — Maths 3 secondary, group A, extended';

CourseTeacherHeroData _data({bool draft = false}) => CourseTeacherHeroData(
      title: _long,
      subtitle: _long,
      crumbRoot: 'دوراتي',
      badges: const [
        CourseSpaceBadge(label: 'منشورة'),
        CourseSpaceBadge(label: 'بث مباشر'),
        CourseSpaceBadge(label: 'خاصة بالكود'),
      ],
      teacherName: 'أ. ماجد الشهري',
      teacherLine: 'الصف الثالث الثانوي',
      pills: const [
        CourseTeacherPill(icon: Icons.groups_rounded, value: '12480', label: 'طلاب'),
        CourseTeacherPill(icon: Icons.payments_rounded, value: '8200', label: 'ريال أرباح'),
        CourseTeacherPill(icon: Icons.video_camera_front_rounded, value: '148', label: 'حصة'),
        CourseTeacherPill(icon: Icons.star_rounded, value: '4.8', label: 'تقييم'),
      ],
      primary: CourseSpaceButton(label: 'حصة جديدة', icon: Icons.add_rounded, onTap: () {}),
      secondary: CourseSpaceButton(label: 'تعديل الدورة', icon: Icons.edit_rounded, onTap: () {}),
      icons: [CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'مشاركة', onTap: () {})],
      menu: [CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'تحديث', onTap: () {})],
      notice: draft ? 'الطلاب ما يشوفون الدورة لين تنشرها' : null,
      onBack: () {},
    );

void main() {
  testWidgets('teacher hero', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: T2Scope(child: CourseTeacherHero(data: _data()))), );
  });

  testWidgets('teacher hero, draft with a notice', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: T2Scope(child: CourseTeacherHero(data: _data(draft: true)))), );
  });

  testWidgets('setup checklist', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: CourseSetupBar(
          badge: 'مسودة',
          steps: const [
            CourseSetupStep('cover', true),
            CourseSetupStep('description', true),
            CourseSetupStep('schedule', false),
            CourseSetupStep('rules', false),
            CourseSetupStep('first_exam', false),
          ],
          onStep: (_) {},
        ),
      ),
    );
  });

  for (final st in MaterialCaptionsState.values) {
    testWidgets('captions panel $st', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(child: MaterialCaptionsPanel(state: st, onUpload: () {}, onGenerate: () {}, onRemove: () {})),
      );
    });
  }
}
