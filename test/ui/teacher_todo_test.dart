// The teacher's automatic to-do list (D-303): the parsers on REAL server answers (test/fixtures/payloads/
// teacher_todo*.json, written by the backend's tests/org_v2/e2e_teacher_todo.py and tests/exam_engine/
// e2e_teacher_todo.py with TODO_FIXTURE_DIR), the engine merge with the core's states, the hidden rule, the filters,
// and every widget at 320x640 / 1400x900, ar + en, textScaler 1.3 (the home card, the full page, its states).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/teacher/home_screen.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_extra.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_page.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/payloads/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final core = TodoList.fromJson(fixture('teacher_todo'));
  final engine = [for (final x in fixture('teacher_todo_engine')['items'] as List) TodoItem.fromJson(x)!];

  setUp(() {
    AppModeController.applyContext = (_) {};
    homeAttentionBadge = (_, child) => child;
  });

  group('parsers on the real answers', () {
    test('core list: every item readable, highest score first, states and hidden kept', () {
      final raw = fixture('teacher_todo');
      expect(core.enabled, isTrue);
      expect(core.items.length, (raw['items'] as List).length);
      expect(core.items.every((x) => x.title.isNotEmpty && x.why.isNotEmpty && x.fp.isNotEmpty && x.actionType.isNotEmpty), isTrue);
      expect([for (final x in core.items) x.score], [for (final x in raw['items'] as List) x['score']]);
      expect(core.totalCount, raw['counts']['total']);
      expect(core.highCount, raw['counts']['high']);
      final risk = core.items.firstWhere((x) => x.kind == 'at_risk');
      expect(risk.students, isNotEmpty);
      expect(risk.students.first.reasons, contains('absent'));
      expect(risk.group, TodoGroup.students);
      final clash = core.items.firstWhere((x) => x.kind == 'conflict', orElse: () => core.hidden.firstWhere((x) => x.kind == 'conflict'));
      expect(clash.when, isNotNull);
      expect(clash.when!.isUtc, isTrue);
      expect(core.states, isNotEmpty);
    });

    test('the /me/home block and an older server', () {
      final block = TodoList.fromJson(fixture('me_home_teacher_todo'));
      expect(block.items.length, lessThanOrEqualTo(3));
      expect(block.totalCount, greaterThanOrEqualTo(block.items.length));
      expect(TeacherHomeExtra.fromJson({'todo': fixture('me_home_teacher_todo')}).todo!.items.length, block.items.length);
      expect(TeacherHomeExtra.fromJson(const {'pending': {}}).todo, isNull); // older server / switched off
      expect(TeacherHomeExtra.fromJson(const {'todo': null}).todo, isNull);
    });

    test('engine items: exam ids, deep links, merged by score with the core states applied', () {
      expect({for (final x in engine) x.kind}, {'exam_grading', 'exam_appeals', 'exam_scan_review'});
      expect(engine.every((x) => x.examId != null && x.group == TodoGroup.grading), isTrue);
      final merged = mergeTodo(core, engine);
      expect(merged.items.length, core.items.length + engine.length);
      for (var i = 1; i < merged.items.length; i++) {
        expect(merged.items[i - 1].score, greaterThanOrEqualTo(merged.items[i].score));
      }
      // a dismissed engine item stays hidden while its evidence is the same, and returns when it changes
      final e = engine.first;
      final states = {...core.states, e.key: TodoState(state: 'dismiss', fp: e.fp)};
      final withState = TodoList(items: core.items, hidden: core.hidden, states: states);
      expect(mergeTodo(withState, engine).hidden.map((x) => x.key), contains(e.key));
      final changed = TodoItem.fromJson({...fixture('teacher_todo_engine')['items'][0] as Map, 'fp': 'other'})!;
      final back = mergeTodo(withState, [changed]).items.firstWhere((x) => x.key == e.key);
      expect(back.returned, isTrue);
    });
  });

  test('hidden rule: done / dismiss by fingerprint, snooze by date', () {
    final now = DateTime.utc(2026, 11, 8, 12);
    expect(todoHidden(const TodoState(state: 'done', fp: 'a'), 'a', now), isTrue);
    expect(todoHidden(const TodoState(state: 'dismiss', fp: 'a'), 'b', now), isFalse);
    expect(todoHidden(TodoState(state: 'snooze', until: now.add(const Duration(hours: 1))), 'x', now), isTrue);
    expect(todoHidden(TodoState(state: 'snooze', until: now.subtract(const Duration(hours: 1))), 'x', now), isFalse);
    expect(todoHidden(null, 'x', now), isFalse);
    expect(todoUtc('2026-11-06T00:53:35.510319')!.isUtc, isTrue);
    expect(todoUtc('2026-11-06T00:53:35Z')!.hour, 0);
  });

  test('filters and the optimistic remove', () {
    final all = mergeTodo(core, engine).items;
    expect(todoFiltered(all, null).length, all.length);
    expect(todoFiltered(all, 'high').every((x) => x.isHigh), isTrue);
    expect(todoFiltered(all, 'grading').map((x) => x.kind).toSet(), containsAll(['exam_grading', 'exam_appeals']));
    final first = core.items.first;
    final less = core.without({first.key});
    expect(less.items.any((x) => x.key == first.key), isFalse);
    expect(less.totalCount, core.totalCount - 1);
  });

  group('layout', () {
    final merged = mergeTodo(core, engine);
    Widget page(TodoList? list, {bool loading = false, String? error}) => TeacherTodoView(
          list: list,
          loading: loading,
          error: error,
          updatedAt: DateTime.now(),
          onRefresh: () async {},
          onOpen: (_) {},
          onMenu: (_, _) {},
          onRestore: (_) {},
          onBack: () {},
        );

    testWidgets('rows: full, compact, hidden', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            for (final x in merged.items) TodoRow(item: x, onOpen: () {}, onMenu: (_) {}),
            for (final x in merged.items.take(3)) TodoRow(item: x, compact: true, onOpen: () {}, onMenu: (_) {}),
            for (final x in merged.hidden) TodoRow(item: x, onRestore: () {}),
          ]),
        ),
      );
    });

    testWidgets('home card and the home body with the to-do', (tester) async {
      final block = TodoList.fromJson(fixture('me_home_teacher_todo'));
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: TeacherTodoSection(list: block, onOpenItem: (_) {}, onMenu: (_, _) {}, onSeeAll: () {}),
        ),
      );
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: TeacherHomeBody(
            loading: false,
            stats: const TeacherStats(totalStudents: 40, totalCourses: 2, overallRating: 4.5),
            schedule: const [],
            pending: const {'attendance_missing': 3, 'grading': 2},
            courses: const [],
            extra: TeacherHomeExtra.fromJson({'todo': fixture('me_home_teacher_todo'), 'earnings': {'month': 10, 'pending_payout': 5}}),
            onTab: (_) {},
            onOpenCourse: (_) {},
            onOpenCourseId: (_) {},
            onNewCourse: () {},
            showFeeds: false,
          ),
        ),
      );
    });

    testWidgets('full page: list, empty, loading, error, switched off, hidden open', (tester) async {
      await expectNoLayoutErrors(tester, () => page(merged));
      await expectNoLayoutErrors(tester, () => page(TodoList.empty));
      await expectNoLayoutErrors(tester, () => page(null, loading: true));
      await expectNoLayoutErrors(tester, () => page(null, error: 'The server did not answer'));
      await expectNoLayoutErrors(tester, () => page(const TodoList(enabled: false)));
      await expectNoLayoutErrors(tester, () => page(merged), act: (t) async {
        await t.ensureVisible(find.byIcon(Icons.expand_more_rounded).first);
        await t.pump();
        await t.tap(find.byIcon(Icons.expand_more_rounded).first);
        await t.pump(const Duration(milliseconds: 400));
      });
    });

    testWidgets('home: the to-do takes over the needs-you pills it covers', (tester) async {
      await tester.pumpWidget(layoutHost(SingleChildScrollView(
        child: TeacherHomeBody(
          loading: false,
          stats: const TeacherStats(totalStudents: 40, totalCourses: 2, overallRating: 4.5),
          schedule: const [],
          pending: const {'attendance_missing': 3, 'grading': 2},
          courses: const [],
          extra: TeacherHomeExtra.fromJson({'todo': fixture('me_home_teacher_todo')}),
          onTab: (_) {},
          onOpenCourse: (_) {},
          onOpenCourseId: (_) {},
          onNewCourse: () {},
          showFeeds: false,
        ),
      )));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(TeacherTodoCard), findsOneWidget);
      expect(find.byType(HomeStatStrip), findsNothing); // attendance / grading are on the to-do now
      await tester.pumpWidget(const SizedBox());
    });
  });
}
