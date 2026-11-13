// A personal student's study data (D-790 – D-796): the model's rules (a stage change drops what no longer applies,
// what is missing, the PUT body, the labels in both languages), the form's chips (stage → grades → track), and every
// new widget at 320 / 1400 wide, ar + en, textScaler 1.3: the form (compact sign-up step, the full profile with
// errors), the home card (alone and inside the student home), the admin's Study block.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/admin/admin_study_profile_settings_page.dart' show StudyProfileSection;
import 'package:flutter_education_app/features/shared/study_profile/study_profile_form.dart';
import 'package:flutter_education_app/features/shared/study_profile/study_profile_model.dart';
import 'package:flutter_education_app/features/shared/study_profile/study_profile_pages.dart' show StudyPromptCard;
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'مدرسة السعيدية الثانوية العسكرية للبنين بالجيزة التابعة لإدارة شمال الجيزة التعليمية';
const longEn = 'Saidia Military Secondary School for Boys, North Giza Educational Administration, Giza';

const full = StudyProfile(
  stage: 'secondary',
  grade: 3,
  track: 'math',
  schoolName: longAr,
  governorate: 'kafr_el_sheikh',
  parentPhone: '+201012345678',
  dob: '2008-04-01',
);

/// The form in a stateful host, so chip taps change it.
class _Host extends StatefulWidget {
  const _Host({required this.initial, this.required = const [], this.showErrors = false, this.compact = false});

  final StudyProfile initial;
  final List<String> required;
  final bool showErrors, compact;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late StudyProfile v = widget.initial;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: StudyProfileForm(
          value: v,
          required: widget.required,
          showErrors: widget.showErrors,
          compact: widget.compact,
          onChanged: (n) => setState(() => v = n),
        ),
      );
}

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('model', () {
    test('a stage change drops a grade it lacks and a track that no longer applies', () {
      expect(full.copyWith(stage: 'preparatory').grade, 3);
      expect(full.copyWith(stage: 'preparatory').track, isNull);
      expect(full.copyWith(stage: 'graduate').grade, isNull);
      expect(const StudyProfile(stage: 'university', grade: 7).copyWith(stage: 'primary').grade, isNull);
      expect(full.copyWith(grade: 1).track, isNull);
      expect(full.copyWith(clearTrack: true).track, isNull);
      expect(full.withText('school_name', '  ').schoolName, isNull);
    });

    test('missing: stage + grade always, the required list, the track only where it applies', () {
      expect(StudyProfile.empty.missing(const []), ['stage', 'grade']);
      expect(const StudyProfile(stage: 'primary').missing(const []), ['grade']);
      expect(const StudyProfile(stage: 'graduate').missing(const []), isEmpty);
      expect(const StudyProfile(stage: 'secondary', grade: 1).missing(const ['track', 'school_name']), ['school_name']);
      expect(const StudyProfile(stage: 'secondary', grade: 2).missing(const ['track']), ['track']);
      expect(full.missing(kStudyOptionalFields), isEmpty);
    });

    test('the PUT body sends every field; city only with other; the sign-up leaves dob out', () {
      final j = full.copyWith(city: 'Riyadh').toJson();
      expect(j.keys.toSet(), {'stage', 'grade', 'track', 'school_name', 'governorate', 'city', 'parent_phone', 'dob'});
      expect(j['city'], isNull);
      expect(full.copyWith(governorate: 'other', city: 'Riyadh').toJson()['city'], 'Riyadh');
      expect(full.toJson(withDob: false).containsKey('dob'), isFalse);
      expect(StudyProfile.fromJson(full.toJson()), full);
    });

    test('labels in both languages', () {
      AppConfig.lang = 'ar';
      expect(full.summary, 'الصف الثالث الثانوي · علمي رياضة');
      expect(const StudyProfile(stage: 'university', grade: 4).summary, 'الفرقة الرابعة');
      AppConfig.lang = 'en';
      expect(full.summary, 'Secondary, grade 3 · Mathematics');
      expect(full.place, '$longAr · Kafr El Sheikh');
      expect(const StudyProfile(stage: 'other').summary, 'Other');
    });

    test('settings: an older server (no block) keeps the step off; unknown fields are dropped', () {
      expect(StudySettings.fromJson(null).signupStep, isFalse);
      final s = StudySettings.fromJson({'signup_step': true, 'home_prompt': false, 'required': ['school_name', 'x']});
      expect((s.signupStep, s.homePrompt), (true, false));
      expect(s.required, ['school_name']);
    });

    test('/me/home: study_prompt read, false when absent', () {
      expect(MeHome.fromJson({'role': 'student', 'study_prompt': true}).studyPrompt, isTrue);
      expect(MeHome.fromJson({'role': 'student'}).studyPrompt, isFalse);
    });
  });

  testWidgets('chips: stage → its grades → the track from secondary 2; the optional part unfolds', (tester) async {
    await tester.pumpWidget(layoutHost(const _Host(initial: StudyProfile.empty, compact: true)));
    expect(find.byKey(const ValueKey('study.grade.1')), findsNothing);
    expect(find.byKey(const ValueKey('study.school')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('study.stage.secondary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study.grade.3')), findsOneWidget);
    expect(find.byKey(const ValueKey('study.grade.4')), findsNothing);
    expect(find.byKey(const ValueKey('study.track.math')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('study.grade.2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study.track.math')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('study.stage.university')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study.grade.7')), findsOneWidget);
    expect(find.byKey(const ValueKey('study.track.math')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('study.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study.more')), findsNothing);
    expect(find.byKey(const ValueKey('study.dob')), findsOneWidget);
  });

  testWidgets('layout: the form (sign-up step, full profile with every error, other + city)', (tester) async {
    await expectNoLayoutErrors(tester, () => const _Host(initial: StudyProfile.empty, compact: true));
    await expectNoLayoutErrors(tester, () => const _Host(initial: full));
    await expectNoLayoutErrors(
      tester,
      () => const _Host(initial: StudyProfile(stage: 'secondary', grade: 2), required: kStudyOptionalFields, showErrors: true),
    );
    await expectNoLayoutErrors(
      tester,
      () => _Host(initial: full.copyWith(stage: 'university', governorate: 'other', city: longEn)),
    );
  });

  testWidgets('layout: the home card, the admin Study block', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        StudyPromptCard(onOpen: () {}, onDismiss: () {}),
        StudyProfileSection(profile: full),
        StudyProfileSection(profile: full.copyWith(governorate: 'other', city: longEn, schoolName: longEn)),
      ]),
    );
  });

  testWidgets('the student home draws the card only with study_prompt and both callbacks', (tester) async {
    MeHome home(bool prompt) => MeHome.fromJson({
          'now': '2026-11-13T09:00:00',
          'today_date': '2026-11-13',
          'timezone': 'Africa/Cairo',
          'role': 'student',
          'today': const [],
          'upcoming': const [],
          'courses_progress': const [],
          'study_prompt': prompt,
        });
    Widget body(bool prompt, {bool callbacks = true}) => SingleChildScrollView(
          child: StudentHomeBody(
            data: StudentHomeData(home: home(prompt), now: DateTime.utc(2026, 11, 13, 9)),
            onTab: (_) {},
            onCompleteStudy: callbacks ? () {} : null,
            onDismissStudy: callbacks ? () {} : null,
          ),
        );
    await expectNoLayoutErrors(tester, () => body(true));
    await tester.pumpWidget(layoutHost(body(true)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StudyPromptCard), findsOneWidget);
    await tester.pumpWidget(layoutHost(body(false)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StudyPromptCard), findsNothing);
    await tester.pumpWidget(layoutHost(body(true, callbacks: false)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StudyPromptCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
