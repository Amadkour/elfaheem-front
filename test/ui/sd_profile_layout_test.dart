// The student's account page (redesign S-D, Stu2Profile): the plain-values view at 320x640 and 1400x900, Arabic and
// English, text scale 1.3, folded and open "إعدادات متقدمة", and its motion parked under Reduce motion.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/features/profile/student_profile_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'اسم طويل جداً لطالب يختبر التفاف النص في البطاقة الأولى من الصفحة';
const _longEn = 'A very long student name that tests the wrapping of the first card on the page';

Widget _row(String label) => AppSettingsTile(icon: Icons.circle_outlined, label: label, subtitle: '$_longAr $_longEn', onTap: () {});

Widget _view({bool open = false}) => SdArea(
      area: AppArea.me,
      child: StudentProfileView(
        hero: StudentProfileHero(name: '$_longAr $_longEn', username: 'faisal.alanazi.long.username', onEdit: () {}),
        shortcuts: [
          for (final (i, a) in AppAccent.values.take(4).indexed)
            SdShortcut(id: '$i', accent: a, icon: Icons.star_outline_rounded, title: '$_longAr $i', meta: _longEn, onTap: () {}),
        ],
        menuA: [for (var i = 0; i < 4; i++) _row('$_longAr $i')],
        menuB: [for (var i = 0; i < 4; i++) _row('$_longEn $i')],
        advanced: [for (var i = 0; i < 6; i++) _row('$_longAr $_longEn $i')],
        exits: [_row('exit')],
        advancedOpen: open,
      ),
    );

void main() {
  testWidgets('student profile view: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, _view);
  });

  testWidgets('student profile view: advanced open', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(open: true));
  });

  testWidgets('student profile view: the advanced card is folded unless asked', (tester) async {
    await tester.pumpWidget(layoutHost(_view(), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('$_longAr $_longEn 0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(layoutHost(_view(open: true), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('$_longAr $_longEn 0', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('student profile view: Reduce motion draws the end state at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(layoutHost(_view(), scale: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('profile.shortcut.0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
