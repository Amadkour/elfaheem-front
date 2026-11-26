// Redesign S-A (auth, home, discover): every new widget through the layout harness (320x640 and 1400x900, ar / en,
// text scale 1.3), the kid-code flow's pure parts, and Reduce motion parking the hero's loops.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/features/auth/account_approval_page.dart';
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/kid_code/kid_code_api.dart';
import 'package:flutter_education_app/features/auth/kid_code/kid_code_screen.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart' show CategoryModel;
import 'package:flutter_education_app/features/courses/category/subject_tiles.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/home/student/home_hero.dart';
import 'package:flutter_education_app/features/onboarding/onboarding_screen.dart';
import 'package:flutter_education_app/features/auth/world_phone_field.dart';
import 'package:flutter_education_app/features/share/share_link_page.dart' show ShareLinkPreviewView;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'الرياضيات للصف الثاني الثانوي، الفصل الدراسي الأول مع مراجعة شاملة لكل الوحدات';
const _longEn = 'Mathematics for grade eleven, first term, with a full review of every unit and chapter';

MeHome _home() => MeHome.fromJson({
      'courses_progress': [
        {'course_id': 1, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics', 'progress': 38, 'next_lecture': {'id': 3, 'name': 'الدوال الأسية'}},
        {'course_id': 2, 'name_ar': 'الفيزياء', 'name_en': 'Physics', 'progress': 64},
        {'course_id': 3, 'name_ar': _longAr, 'name_en': _longEn, 'progress': 81},
        {'course_id': 4, 'name_ar': 'الكيمياء', 'name_en': 'Chemistry', 'progress': 100},
      ],
    });

Widget _scoped(Widget child) => AppAreaScope(area: AppArea.home, child: child);

void main() {
  test('kid code digits: Arabic-Indic, spaces and dashes', () {
    expect(kidCodeDigits('٤٨٢ ٩١٧'), '482917');
    expect(kidCodeDigits('482-917'), '482917');
    expect(kidPasswordStrength('abc'), 0);
    expect(kidPasswordStrength('Abcdefgh12'), 4);
  });

  test('course subject from a title', () {
    expect(courseSubjectKeyOf('الرياضيات ٢ ثانوي، الفصل الأول'), 'math');
    expect(courseSubjectKeyOf('الفيزياء: الحركة والقوى'), 'physics');
    expect(courseSubjectKeyOf('Unit 4: Daily routines', subject: 'english'), 'english');
    expect(courseSubjectKeyOf('Something else'), 'other');
  });

  test('hero line: live first, then the course to pick up, else a free day', () {
    AppConfig.lang = 'en';
    final featured = _home().coursesProgress.first;
    final free = studentHeroLine(), picked = studentHeroLine(featured: featured);
    expect(picked.title, isNot(free.title));
    expect(free.squiggle, isNotNull);
    expect(studentHeroLine(guest: true, featured: featured).title, isNot(picked.title));
  });

  testWidgets('auth layout with a glyph and a hero line', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => AuthLayout(
        kicker: _longAr,
        heroTitle: '$_longAr $_longEn',
        squiggle: 'الثانوي',
        title: _longAr,
        subtitle: _longEn,
        glyph: Icons.key_rounded,
        actions: (onHero) => AuthLangButton(arabic: true, onHero: onHero, onTap: () {}),
        body: (context, wide) => const SizedBox(height: 120),
      ),
    );
  });

  testWidgets('kid code: the three steps', (tester) async {
    const account = KidCodeAccount(firstName: _longAr, lastName: _longEn, gradeAr: 'الثاني ثانوي', parentName: _longAr);
    for (final w in <Widget Function()>[
      () => KidCodeEnterView(controller: TextEditingController(text: '4829'), onSubmit: () {}, onBack: () {}, error: _longAr),
      () => KidCodeFoundView(account: account, onYes: () {}, onNo: () {}),
      () => KidCodePassView(controller: TextEditingController(text: 'Abcdef12345'), onSubmit: () {}, error: _longEn),
      () => KidCodeEntryTile(onTap: () {}),
    ]) {
      await expectNoLayoutErrors(tester, () => _scoped(SingleChildScrollView(child: w())));
    }
  });

  testWidgets('kid code boxes take Arabic-Indic digits and stop at six', (tester) async {
    final c = TextEditingController();
    var done = 0;
    await tester.pumpWidget(layoutHost(_scoped(KidCodeBoxes(controller: c, onCompleted: () => done++)), scale: 1));
    await tester.enterText(find.byType(TextField), '٤٨٢٩١٧٥');
    await tester.pump();
    expect(c.text, '482917');
    expect(done, greaterThan(0));
  });

  testWidgets('approval: waiting and needs a change', (tester) async {
    for (final rejected in [false, true]) {
      await expectNoLayoutErrors(
        tester,
        () => _scoped(SingleChildScrollView(
          child: AccountApprovalView(
            rejected: rejected,
            reason: rejected ? _longAr : null,
            paidFirst: true,
            onCheck: () {},
            onContact: () {},
            onSignOut: () {},
          ),
        )),
      );
    }
  });

  testWidgets('home hero, top bar and the continue card', (tester) async {
    final h = _home();
    await expectNoLayoutErrors(
      tester,
      () => _scoped(SingleChildScrollView(
        child: Column(children: [
          StudentHomeTopBar(actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded))]),
          StudentHomeHero(
            name: _longAr,
            home: h,
            line: studentHeroLine(featured: h.coursesProgress.first),
            daySummary: _longEn,
            now: DateTime.utc(2026, 11, 25, 9),
          ),
          StudentContinueCard(courses: h.coursesProgress, onOpen: (_) {}, onShowAll: () {}, streakDays: 5),
        ]),
      )),
    );
  });

  testWidgets('subject tiles and the course card', (tester) async {
    final cats = [
      for (final n in ['الرياضيات', 'الفيزياء', 'الكيمياء', _longAr]) CategoryModel(id: n, nameAr: n, nameEn: _longEn, imageUrl: null, description: ''),
    ];
    await expectNoLayoutErrors(
      tester,
      () => _scoped(SingleChildScrollView(
        child: Column(children: [
          SubjectsCard(categories: cats, onOpen: (_) {}, onAll: () {}),
          for (final shape in CourseCardShape.values)
            CourseListCard(
              shape: shape,
              title: _longAr,
              imageUrl: '',
              meta: const [_longEn, '24'],
              chip: const CourseCoverChip(label: _longAr),
              footer: const CourseProgressFooter(progress: 38),
            ),
        ]),
      )),
    );
  });

  test('world phone: fixed lengths, else E.164', () {
    const sa = WorldCountry(code: 'SA', nameAr: 'السعودية', nameEn: 'Saudi Arabia', dial: '+966', minLen: 9, maxLen: 9);
    const gb = WorldCountry(code: 'GB', nameAr: 'بريطانيا', nameEn: 'United Kingdom', dial: '+44');
    expect(sa.validLength('501234567'), isTrue);
    expect(sa.validLength('50123456'), isFalse);
    expect(gb.validLength('7400123456'), isTrue);
    expect(gb.validLength('12345'), isFalse);
  });

  testWidgets('world phone field and the share preview with price and outcomes', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scoped(SingleChildScrollView(
        child: Column(children: [
          Form(child: WorldPhoneField(controller: TextEditingController(text: '+966501234567'), label: _longAr)),
          SizedBox(
            height: 900,
            child: ShareLinkPreviewView(
              kind: _longAr,
              icon: Icons.school_rounded,
              title: _longAr,
              subtitle: _longEn,
              isPublic: true,
              price: '199 SAR / month',
              outcomes: const [_longAr, _longEn, 'x'],
              onSignIn: () {},
              onRegister: () {},
            ),
          ),
        ]),
      )),
    );
  });

  testWidgets('onboarding on the hero', (tester) async {
    await expectNoLayoutErrors(tester, () => OnboardingScreen(onLanguage: (_) {}, onFinish: () {}), scaffold: false);
  });

  testWidgets('Reduce motion parks the hero loops (the page settles)', (tester) async {
    await tester.pumpWidget(layoutHost(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: AuthLayout(
          kicker: 'k',
          heroTitle: 'hero word',
          squiggle: 'word',
          title: 't',
          body: (context, wide) => const SizedBox(height: 40),
        ),
      ),
      scale: 1,
    ));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
