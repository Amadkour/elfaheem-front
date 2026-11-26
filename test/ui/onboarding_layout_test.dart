import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/onboarding/guest_search_screen.dart';
import 'package:flutter_education_app/features/onboarding/landing_api.dart';
import 'package:flutter_education_app/features/onboarding/onboarding_screen.dart';
import 'package:flutter_education_app/features/onboarding/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart' show AuthButton;

import 'layout_harness.dart';

const _subjects = [
  LandingSubject(id: 1, nameAr: 'الرياضيات', nameEn: 'Mathematics', courses: 12, levels: [
    LandingLevel(id: 11, nameAr: 'الصف الثالث الثانوي', nameEn: 'Grade 12 (final secondary year)', courses: 5),
    LandingLevel(id: 12, nameAr: 'الصف الثاني الثانوي', nameEn: 'Grade 11', courses: 7),
  ]),
  LandingSubject(id: 2, nameAr: 'اللغة الإنجليزية', nameEn: 'English language', courses: 3),
];

Future<List<LandingSubject>> _options() async => _subjects;
Future<LandingCount?> _match({int? subject, int? level, required String mode}) async => const LandingCount(courses: 12, teachers: 7);

void main() {
  setUp(() => OnboardingStore.resetForTest());

  testWidgets('OnboardingScreen has no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => OnboardingScreen(onLanguage: (_) {}, onFinish: () {}), scaffold: false);
  });

  testWidgets('OnboardingScreen last page', (tester) async {
    await expectNoLayoutErrors(tester, () => OnboardingScreen(onLanguage: (_) {}, onFinish: () {}), scaffold: false, act: (t) async {
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byType(AuthButton), warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 400));
      }
    });
  });

  testWidgets('GuestSearchScreen has no layout errors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => GuestSearchScreen(loadOptions: _options, loadMatch: _match, onShow: (_, _) {}, onLogin: () {}, onRegister: () {}),
      scaffold: false,
      frames: 6,
    );
  });

  testWidgets('GuestSearchScreen fails soft with no data', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => GuestSearchScreen(loadOptions: () async => const [], loadMatch: ({subject, level, required mode}) async => null),
      scaffold: false,
      frames: 6,
    );
  });

  testWidgets('GuestSearchScreen shows the count and passes the level to Show courses', (tester) async {
    int? shown;
    String? shownMode;
    await tester.pumpWidget(layoutHost(
      GuestSearchScreen(loadOptions: _options, loadMatch: _match, onShow: (id, m) {
        shown = id;
        shownMode = m;
      }),
      scaffold: false,
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('12'), findsWidgets);
    // the dropdowns above draw their labels above the well, so the mode chips sit below the 600 px test view
    await tester.ensureVisible(find.byType(ChoiceChip).at(1));
    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
    await tester.pump();
    expect(shownMode, 'online');
    expect(shown, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
