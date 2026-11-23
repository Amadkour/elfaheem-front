// Games v4 G3: the reward rule form picks its courses by search (not typed ids). Two courses picked through a fake
// API end up in the saved body; a saved rule shows its courses' names; "Selected courses" with none blocks save;
// the field and the search sheet lay out at 320 and 1400 px, ar + en, text 1.3.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_api.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_page.dart';
import 'package:flutter_education_app/features/admin/rewards/reward_course_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _courses = [
  RewardsCourse(id: 4, nameAr: 'الجبر', nameEn: 'Algebra', teacher: 'Mona'),
  RewardsCourse(id: 9, nameAr: 'الفيزياء', nameEn: 'Physics', teacher: 'Omar'),
  RewardsCourse(
    id: 12,
    nameAr: 'دورة باسم طويل جداً جداً لاختبار الالتفاف على الشاشات الصغيرة',
    nameEn: 'A course with a very very long name to test wrapping on small screens',
    teacher: 'A teacher with a long name too',
  ),
];

class _FakeApi implements AdminRewardsApi {
  final queries = <String>[];

  @override
  Future<List<RewardsCourse>> searchCourses(String q, {int size = 30}) async {
    queries.add(q);
    final s = q.toLowerCase();
    return [for (final c in _courses) if (s.isEmpty || c.name.toLowerCase().contains(s)) c];
  }

  @override
  Future<RewardsCourse> course(int id) async => _courses.firstWhere((c) => c.id == id);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _form(_FakeApi api, RewardRule rule, void Function(RewardRule) onSaved) => SingleChildScrollView(
      child: RewardRuleForm(initial: rule, api: api, onSubmit: (d) async => onSaved(d)),
    );

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('admin.rewards.form.save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump();
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('two courses picked by search are saved as ids', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = _FakeApi();
    RewardRule? saved;
    await tester.pumpWidget(layoutHost(_form(api, const RewardRule(appliesTo: 'course', courseIds: []), (d) => saved = d)));
    await tester.pumpAndSettle();
    expect(find.text('No courses chosen yet'), findsOneWidget);

    // "Selected courses" with none chosen blocks save
    await _tapSave(tester);
    expect(saved, isNull);
    expect(find.textContaining('Choose at least one course'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin.rewards.form.course_add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin.rewards.course.4')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin.rewards.course.4')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('admin.rewards.course_search')), matching: find.byType(TextField)), 'phys');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.queries.last, 'phys');
    expect(find.byKey(const ValueKey('admin.rewards.course.4')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin.rewards.course.9')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin.rewards.course_done')));
    await tester.pumpAndSettle();

    expect(find.text('Algebra · Mona'), findsOneWidget);
    expect(find.text('Physics · Omar'), findsOneWidget);
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(saved?.courseIds, [4, 9]);
    expect(saved?.toJson()['course_ids'], [4, 9]);
  });

  testWidgets('a saved rule shows its course names; removing a chip drops the id', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    RewardRule? saved;
    await tester.pumpWidget(layoutHost(_form(_FakeApi(), const RewardRule(id: 3, appliesTo: 'course', courseIds: [4, 9]), (d) => saved = d)));
    await tester.pumpAndSettle();
    expect(find.text('Algebra · Mona'), findsOneWidget);
    expect(find.text('Physics · Omar'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin.rewards.form.course_ids')), findsNothing);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('admin.rewards.form.course_chip.4')), matching: find.byTooltip('Remove')));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(saved?.courseIds, [9]);
  });

  testWidgets('without a resolver a saved id shows "Course #id"', (tester) async {
    await tester.pumpWidget(layoutHost(RewardCoursesField(initialIds: const [77], onChanged: (_) {}, search: (_) async => const [])));
    await tester.pump();
    expect(find.text('Course #77'), findsOneWidget);
  });

  testWidgets('field and search sheet lay out', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _form(_FakeApi(), const RewardRule(appliesTo: 'course', courseIds: [4, 9, 12, 55]), (_) {}),
    );
    await expectNoLayoutErrors(
      tester,
      () => _form(_FakeApi(), const RewardRule(appliesTo: 'course', courseIds: [4]), (_) {}),
      act: (tester) async {
        final add = find.byKey(const ValueKey('admin.rewards.form.course_add'));
        await tester.ensureVisible(add);
        await tester.tap(add);
      },
    );
    await expectNoLayoutErrors(tester, () => RewardCourseSearchSheet(search: (_) async => const []));
    await expectNoLayoutErrors(tester, () => RewardCourseSearchSheet(search: (_) => Completer<List<RewardsCourse>>().future));
  });
}
