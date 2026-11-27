// The teacher's course wizard (T1 Wizard): every step in create and edit mode at every layout size, in both
// languages, with the large text scale; the step rules (what stops Next), the weekly slot sheet, the privacy code.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show showAppSheet;
import 'package:flutter_education_app/features/courses/teacher/course_privacy_card.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/weekly_slot_sheet.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/redesign/t1_wizard_fakes.dart';
import 'layout_harness.dart';

void _loadStrings() {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  for (final f in Directory('docs/redesign/strings').listSync().whereType<File>()) {
    if (f.path.endsWith('.json')) translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }
}

/// Taps "Next" [n] times (each step's rules must pass: the demo course is complete).
Future<void> _next(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    final b = find.byKey(const ValueKey('wizard.next'));
    await t.ensureVisible(b);
    await t.tap(b);
    for (var k = 0; k < 4; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  setUp(() async {
    _loadStrings();
    await t1WizardSetUp(t1WizardApi());
  });

  group('every step lays out (edit mode, the demo course)', () {
    for (final s in CourseWizardStep.values) {
      testWidgets(s.name, (t) async {
        await expectNoLayoutErrors(
          t,
          () => t1WizardForm(course: t1WizardCourse()),
          scaffold: false,
          frames: 8,
          act: (t) async {
            await _next(t, s.index);
            expect(find.text(wizardStepLine(s)), findsOneWidget, reason: 'reached the ${s.name} step');
          },
        );
      });
    }
  });

  testWidgets('create mode: the first step lays out', (t) async {
    await expectNoLayoutErrors(t, () => t1WizardForm(), scaffold: false, frames: 8);
  });

  testWidgets('create mode: Next waits for a title, then moves on and Back returns', (t) async {
    AppConfig.lang = 'en';
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(t1WizardForm(), scale: 1, scaffold: false));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await _next(t, 1);
    expect(find.byKey(const ValueKey('wizard.plan.0')), findsNothing, reason: 'no title: still on the first step');
    final titleAr = find.byType(TextFormField).first;
    await t.enterText(titleAr, 'الرياضيات ٣ ثانوي');
    await t.pump();
    await _next(t, 1);
    expect(find.byKey(const ValueKey('wizard.plan.0')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wizard.back')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('wizard.plan.0')), findsNothing);
  });

  testWidgets('edit mode: the steps strip jumps anywhere; the review lists the course and the ready count', (t) async {
    AppConfig.lang = 'en';
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(t1WizardForm(course: t1WizardCourse()), scale: 1, scaffold: false));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('wizard.steps')), findsOneWidget);
    await _next(t, 6);
    expect(find.byKey(const ValueKey('wizard.ready')), findsOneWidget);
    expect(find.text('Ready 5 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard.review.schedule')), findsOneWidget);
  });

  group('the weekly slot sheet', () {
    Widget host({List<WeeklySlotValue> existing = const [], WeeklySlotValue? initial}) => Builder(
          builder: (c) => Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(c, (_) => LocalAddScheduleSheet(existing: existing, initial: initial, onAdd: (_, _, _) {})),
              child: const Text('open'),
            ),
          ),
        );

    Future<void> open(WidgetTester t) async {
      await t.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('new slot, a second slot on the same day, an edit', (t) async {
      await expectNoLayoutErrors(t, () => host(), act: open);
      await expectNoLayoutErrors(t, () => host(existing: [(day: 'monday', start: '19:30', end: '20:20')]), act: open);
      await expectNoLayoutErrors(t, () => host(initial: (day: 'tuesday', start: '19:30', end: '20:20')), act: open);
    });

    testWidgets('a same-day slot shows the warning and "Yes, add it"; a free day does not', (t) async {
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(host(existing: [(day: 'monday', start: '19:30', end: '20:20')])));
      await open(t);
      expect(find.byKey(const ValueKey('wizard.slot.same_day')), findsOneWidget);
      expect(find.text('Yes, add it'), findsOneWidget);
      await t.tap(find.text('Tue'));
      await t.pump();
      expect(find.byKey(const ValueKey('wizard.slot.same_day')), findsNothing);
    });

    testWidgets('adding hands back the day and the 50-minute slot', (t) async {
      AppConfig.lang = 'en';
      WeeklySlotValue? got;
      await t.pumpWidget(layoutHost(Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => showAppSheet<void>(c, (_) => LocalAddScheduleSheet(existing: const [], onAdd: (d, s, e) => got = (day: d, start: s, end: e))),
            child: const Text('open'),
          ),
        ),
      )));
      await open(t);
      await t.tap(find.text('Tue'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('wizard.slot.add')));
      await t.pump(const Duration(milliseconds: 300));
      expect(got, (day: 'tuesday', start: '16:00', end: '16:50'));
    });
  });

  group('the privacy card', () {
    Widget card(bool priv, TextEditingController ctrl) => StatefulBuilder(
          builder: (_, set) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(child: CoursePrivacyCard(isPrivate: priv, codeCtrl: ctrl, onChanged: (_) {})),
          ),
        );

    testWidgets('public, private with a code, private with a short code', (t) async {
      await expectNoLayoutErrors(t, () => card(false, TextEditingController()));
      await expectNoLayoutErrors(t, () => card(true, TextEditingController(text: '482917')));
      await expectNoLayoutErrors(t, () => card(true, TextEditingController(text: '48')));
    });

    test('the code rule is unchanged: empty is fine, six digits, nothing else', () {
      expect(CoursePrivacyCard.validateCode(false, 'abc'), isNull);
      expect(CoursePrivacyCard.validateCode(true, ''), isNull);
      expect(CoursePrivacyCard.validateCode(true, '482917'), isNull);
      expect(CoursePrivacyCard.validateCode(true, '4829'), isNotNull);
    });
  });

  group('plain pieces', () {
    testWidgets('code boxes, week strip, slot row', (t) async {
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(padding: EdgeInsets.all(16), child: WzCodeBoxes(code: '482')));
      await expectNoLayoutErrors(
        t,
        () => const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: WzWeekStrip(days: [('السبت', null), ('الأحد', '7:30 م'), ('الاثنين', null), ('الثلاثاء', '7:30 م'), ('الأربعاء', null), ('الخميس', '4:00 م'), ('الجمعة', null)]),
        ),
      );
      await expectNoLayoutErrors(
        t,
        () => Padding(padding: const EdgeInsets.all(16), child: WzSlotRow(day: 'الأحد', range: '7:30 – 8:20', length: 'حصة 50 دقيقة', onEdit: () {}, onDelete: () {})),
      );
    });

    test('per-month, minutes and the step lines', () {
      AppConfig.lang = 'en';
      expect(wizardPerMonth('450', 12), '37.5');
      expect(wizardPerMonth('260', 6), '43.3');
      expect(wizardPerMonth('', 6), '');
      expect(wizardMinutes('19:30', '20:20'), 50);
      expect(wizardMinutes('20:00', '19:00'), 0);
      expect(wizardStepLine(CourseWizardStep.pricing), 'Step 2 of 7: Pricing');
      expect(wizardNextLine(CourseWizardStep.review), 'Next: Publish');
      AppConfig.lang = 'ar';
      expect(wizardStepLine(CourseWizardStep.basics), contains('الأساسيات'));
    });
  });
}
