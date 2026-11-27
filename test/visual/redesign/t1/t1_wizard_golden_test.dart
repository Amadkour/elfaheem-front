// VISUAL review renders of the teacher's course wizard (Tea1Wizard): the seven steps and the weekly-slot sheet at
// 390x844 and 1360x900, CAST demo data (test/support/redesign/t1_wizard_fakes.dart), compared by eye with
// D:/platform/redesign-ref/ref/teacher/018..025_Tea1Wizard_*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_wizard_golden_test.dart --update-goldens [--plain-name pricing]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/t1_wizard_fakes.dart';
import '../kit_golden_harness.dart';

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
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, int step, {List<String> langs = const ['ar'], bool create = false, Future<void> Function(WidgetTester)? after}) async {
    await t1WizardSetUp(t1WizardApi());
    await kitRender(
      tester,
      't1/wizard_$name',
      () => t1WizardForm(course: create ? null : t1WizardCourse()),
      storage: storage,
      modes: const [false],
      langs: langs,
      scaffold: false,
      act: (t) async {
        await _next(t, step);
        await after?.call(t);
      },
    );
  }

  const both = ['ar', 'en'];
  testWidgets('wizard basics', (t) => render(t, 'basics', CourseWizardStep.basics.index, langs: both));
  testWidgets('wizard basics (create)', (t) => render(t, 'basics_create', 0, create: true));
  testWidgets('wizard pricing', (t) => render(t, 'pricing', CourseWizardStep.pricing.index, langs: both));
  testWidgets('wizard audience', (t) => render(t, 'audience', CourseWizardStep.audience.index));
  testWidgets('wizard privacy', (t) => render(t, 'privacy', CourseWizardStep.privacy.index));
  testWidgets('wizard schedule', (t) => render(t, 'schedule', CourseWizardStep.schedule.index));
  testWidgets('wizard schedadd', (t) => render(t, 'schedadd', CourseWizardStep.schedule.index, after: (t) async {
        await t.tap(find.byKey(const ValueKey('wizard.slot.new')));
        for (var k = 0; k < 6; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }));
  testWidgets('wizard extras', (t) => render(t, 'extras', CourseWizardStep.extras.index));
  testWidgets('wizard review', (t) => render(t, 'review', CourseWizardStep.review.index, langs: both));
}
