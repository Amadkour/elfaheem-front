// D-290 phase 6: the teacher detail and the categories list + detail over a FakeApi serving the real entity payloads,
// seen by an admin (`can.manage`).
//
//   teacher    a row opens the panel with its loaded courses and students; the course rows leave the teacher out; the
//              management sheet's controls unfold inside the detail and a change reloads detail and list; Delete closes
//              the panel; Message opens addressed to the teacher
//   categories the server pages the list (rows with teachers and students, sorts by people); a row opens the detail
//              with one tab per connected list with its count; a tab loads on its first visit, its filter reaches the
//              server, a student opened from a tab comes back to that tab; Edit and Delete work from the detail;
//              Teacher → course → category walks the trail (scenario 3)
//   full page  Manage is there too, with no list behind it
//   layout     320 x 640 and 1400 x 900, ar / en, text 1.3, management unfolded
//   a11y       the guidelines over the categories page with a detail open
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/admin/admin_categories_page.dart';
import 'package:flutter_education_app/features/admin/admin_send_message_page.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../a11y_guidelines_test.dart' show expectA11y;
import '../admin_ds/people_support.dart';
import '../layout_harness.dart';
import 'md_support.dart';

/// One category row of `GET /admin/categories` (`_cat_row` + `_category_people`).
Map<String, dynamic> categoryRow(int i) => {
      'id': 5 + i,
      'name_ar': i.isEven ? 'علوم الحاسب ${i + 1}' : 'الرياضيات والفيزياء التطبيقية ${i + 1}',
      'name_en': i.isEven ? 'Computer Science ${i + 1}' : 'Applied Maths ${i + 1}',
      'description': i % 3 == 0 ? null : 'Programming, data and the craft of software.',
      'parent_id': null,
      'image_url': null,
      'courses_count': 12 - i,
      'teachers_count': 5,
      'students_count': 240 - i * 10,
    };

/// The paged route, as the server answers once `page` is sent.
Object? categoriesList(RequestOptions o) {
  final page = int.parse(o.uri.queryParameters['page'] ?? '1');
  final size = int.parse(o.uri.queryParameters['size'] ?? '20');
  final all = [for (var i = 0; i < 25; i++) categoryRow(i)];
  return {
    'items': all.skip((page - 1) * size).take(size).toList(),
    'total': all.length,
    'page': page,
    'size': size,
    'pages': (all.length / size).ceil(),
  };
}

/// [entitiesHandler] as an admin sees it: `can.manage` on a teacher and a category, with the fields of each.
Object? adminEntities(RequestOptions o) {
  final r = entitiesHandler(o);
  final segs = o.uri.pathSegments;
  if (r is Map<String, dynamic> && segs[segs.length - 2] == 'teachers') {
    (r['header'] as Map)['organizations'] = [
      {'id': 3, 'name_ar': 'جامعة النيل', 'name_en': 'Nile University'},
    ];
    r['can'] = {'manage': true, 'message': true, 'see_money': true};
    r['badges'] = [
      {'code': 'top_rated', 'level': 'good', 'value': 4.7},
      {'code': 'low_engagement', 'level': 'warn', 'value': 18.0},
    ];
  } else if (r is Map<String, dynamic> && segs[segs.length - 2] == 'categories') {
    r['can'] = {'manage': true, 'message': false, 'see_money': true};
    (r['stats'] as Map)
      ..['courses'] = 0
      ..['teachers'] = 4
      ..['students'] = 31;
    (r['header'] as Map)['children'] = const [];
  }
  return r;
}

Map<String, FakeHandler> adminRoutes({String role = 'teacher'}) => {
      ...peopleRoutes(detailRole: role),
      'GET /api/v1/entities/*': adminEntities,
      'GET /api/v1/admin/categories': categoriesList,
      'PUT /api/v1/admin/categories/*': (_) => {'id': 5},
      'DELETE /api/v1/admin/categories/*': (_) => {'ok': true},
    };

/// The providers of the app above [child] (the categories page follows the language).
Widget hosted(MyAuthProvider auth, Widget child) =>
    ChangeNotifierProvider(create: (_) => LangProvider(storage: peopleStorage), child: peopleProviders(auth, child));

Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeApi api;

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  Future<MyAuthProvider> start() async {
    final auth = await peopleSetUp(api);
    // the new strings wait in keys_p6.json until they are merged (peopleSetUp reads the translation file again)
    translation.addAll(jsonDecode(File('docs/master_detail/keys_p6.json').readAsStringSync()) as Map<String, dynamic>);
    return auth;
  }

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    debugClearAppTableLayouts();
    EntitiesApi.instance.invalidate();
    api = FakeApi(adminRoutes(), latency: const Duration(milliseconds: 5));
  });

  void window(WidgetTester tester, [Size size = const Size(1500, 1400)]) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> teachersPage(WidgetTester tester, {Size size = const Size(1500, 1400)}) async {
    window(tester, size);
    final auth = await start();
    await tester.pumpWidget(hosted(auth, layoutHost(const AdminUsersPage(role: 'teacher', embedded: true), scale: 1)));
    await frames(tester);
  }

  Future<void> categoriesPage(WidgetTester tester, {Size size = const Size(1500, 1400)}) async {
    window(tester, size);
    final auth = await start();
    await tester.pumpWidget(hosted(auth, layoutHost(const AdminCategoriesPage(), scale: 1)));
    await frames(tester);
  }

  EntityPanelController panelOf(WidgetTester tester) =>
      tester.widget<MasterDetailScaffold>(find.byType(MasterDetailScaffold)).controller;

  Future<void> tapRow(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await frames(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await frames(tester);
  }

  group('teacher', () {
    testWidgets('a row opens the connected detail, with its loaded lists', (tester) async {
      await teachersPage(tester);
      await tapRow(tester, 'Omar Khaled 2');
      expect(panelOf(tester).current, const EntityRef(EntityKind.teacher, 101));
      expect(find.textContaining('Nile University'), findsOneWidget, reason: 'the organization in the header');
      expect(find.text('Top rated · ${'⁦'}4.7${'⁩'}'), findsOneWidget);
      expect(find.text(mdCourses[0].$2), findsOneWidget, reason: 'the courses section loaded');
      expect(find.text('سارة أحمد'), findsOneWidget, reason: 'the students section loaded');
      expect(api.calls.map((c) => c.path), containsAll(['/api/v1/entities/teachers/101/courses', '/api/v1/entities/teachers/101/students']));
      final completion = find.textContaining('Completion');
      expect(completion, findsWidgets);
      // a teacher's course rows name the category, never the teacher again
      final row = find.ancestor(of: find.text(mdCourses[0].$2), matching: find.byType(Column)).first;
      expect(find.descendant(of: row, matching: find.text('Computer Science')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining(mdTeachers[0])), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Manage unfolds the sheet in the detail; a change reloads the detail and the list', (tester) async {
      await teachersPage(tester);
      await tapRow(tester, 'Omar Khaled 2');
      expect(find.byKey(const ValueKey('admin.user_edit')), findsNothing);
      await tapKey(tester, 'md.manage');
      for (final key in const ['admin.user_edit', 'admin.user_verify', 'admin.user_deactivate', 'admin.user_delete', 'admin.user_mfa_reset']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('admin_teacher_profile'.tr), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('md.inline')), matching: find.text('user1@example.test')), findsOneWidget,
          reason: 'the profile of the sheet');
      expect(find.byKey(const ValueKey('admin.user_view_as')), findsNothing, reason: 'the detail has View as already');
      expect(find.byKey(const ValueKey('md.view_as')), findsOneWidget);

      final before = api.calls.where((c) => c.path == '/api/v1/entities/teachers/101').length;
      final listBefore = api.calls.where((c) => c.path == '/api/v1/admin/users').length;
      await tapKey(tester, 'admin.user_verify');
      await tester.tap(find.byType(FilledButton).last);
      await frames(tester, 14);
      expect(api.calls.where((c) => c.method == 'PUT' || c.method == 'POST').isNotEmpty, isTrue);
      expect(api.calls.where((c) => c.path == '/api/v1/entities/teachers/101').length, greaterThan(before), reason: 'the detail reloaded');
      expect(api.calls.where((c) => c.path == '/api/v1/admin/users').length, greaterThan(listBefore), reason: 'the list reloaded');
      expect(find.byKey(const ValueKey('admin.user_edit')), findsOneWidget, reason: 'the block stays unfolded');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Delete from the detail closes the panel', (tester) async {
      await teachersPage(tester);
      await tapRow(tester, 'Omar Khaled 2');
      await tapKey(tester, 'md.manage');
      await tapKey(tester, 'admin.user_delete');
      await tester.tap(find.byType(FilledButton).last);
      await frames(tester, 14);
      expect(api.calls.map((c) => '${c.method} ${c.path}'), contains('DELETE /api/v1/admin/users/101'));
      expect(panelOf(tester).isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Message opens addressed to this teacher', (tester) async {
      await teachersPage(tester);
      await tapRow(tester, 'Omar Khaled 2');
      await tapKey(tester, 'md.message');
      final page = tester.widget<AdminSendMessagePage>(find.byType(AdminSendMessagePage));
      expect(page.teacher?['id'], 101);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a course, then its category: the trail of scenario 3', (tester) async {
      await teachersPage(tester);
      await tapRow(tester, 'Omar Khaled 2');
      await tester.tap(find.text(mdCourses[0].$2).first);
      await frames(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('Category: Computer Science')).first);
      await frames(tester);
      final c = panelOf(tester);
      expect(c.trail.map((r) => r.kind), [EntityKind.teacher, EntityKind.course, EntityKind.category]);
      expect(find.byType(EntityConnectedTabs), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('categories', () {
    testWidgets('the list pages on the server and shows people; a row opens the tabs with their counts', (tester) async {
      await categoriesPage(tester);
      final list = api.calls.firstWhere((c) => c.path == '/api/v1/admin/categories');
      expect(list.query['page'], '1');
      expect(find.text('Computer Science 1'), findsOneWidget);
      expect(find.text('240'), findsOneWidget, reason: 'the students column');
      await tapRow(tester, 'Computer Science 1');
      expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
      final tabs = tester.widget<AppUnderlineTabs>(find.byType(AppUnderlineTabs));
      expect([for (final t in tabs.items) t.count], [0, 4, 31]);
      expect(find.text('Computer Science'), findsWidgets);
      expect(find.text(mdCourses[1].$2), findsWidgets, reason: 'the first tab loaded');
      // the other lists wait for their tab
      expect(api.calls.map((c) => c.path), isNot(contains('/api/v1/entities/categories/5/students')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tab with its filter; a student opened from it comes back to it', (tester) async {
      await categoriesPage(tester);
      await tapRow(tester, 'Computer Science 1');
      // the tab strip scrolls when the test's wide font does not fit the panel
      final tab = find.descendant(of: find.byType(AppUnderlineTabs), matching: find.text('md_sec_students'.tr));
      await tester.ensureVisible(tab);
      await frames(tester, 4);
      await tester.tap(tab);
      await frames(tester);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/categories/5/students'));
      await tester.tap(find.text('md_p6_activity_inactive'.tr));
      await frames(tester);
      final filtered = api.calls.lastWhere((c) => c.path == '/api/v1/entities/categories/5/students');
      expect(filtered.query['activity'], 'inactive');

      await tester.tap(find.text('Omar Khaled').first);
      await frames(tester);
      final c = panelOf(tester);
      expect(c.current?.kind, EntityKind.student, reason: 'the student opens on top of the same page');
      c.back();
      await frames(tester);
      final tabs = tester.widget<AppUnderlineTabs>(find.byType(AppUnderlineTabs));
      expect(tabs.index, 2, reason: 'back on the Students tab');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Edit in the detail saves, reloads the detail and the list', (tester) async {
      await categoriesPage(tester);
      await tapRow(tester, 'Computer Science 1');
      final before = api.calls.where((c) => c.path == '/api/v1/admin/categories').length;
      await tapKey(tester, 'md.category_edit');
      await tester.tap(find.text('save'.tr).last);
      await frames(tester, 14);
      expect(api.calls.map((c) => '${c.method} ${c.path}'), contains('PUT /api/v1/admin/categories/5'));
      expect(api.calls.where((c) => c.path == '/api/v1/admin/categories').length, greaterThan(before));
      expect(find.byType(EntityConnectedTabs), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Delete in the detail closes the panel', (tester) async {
      await categoriesPage(tester);
      await tapRow(tester, 'Computer Science 1');
      await tapKey(tester, 'md.category_delete');
      await tester.tap(find.byType(FilledButton).last);
      await frames(tester, 14);
      expect(api.calls.map((c) => '${c.method} ${c.path}'), contains('DELETE /api/v1/admin/categories/5'));
      expect(panelOf(tester).isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sort reaches the server', (tester) async {
      await categoriesPage(tester);
      await tester.tap(find.text('md_stat_students'.tr).first);
      await frames(tester);
      final last = api.calls.lastWhere((c) => c.path == '/api/v1/admin/categories');
      expect(last.query['sort'], 'most_students');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a phone opens the sheet from a card', (tester) async {
      await categoriesPage(tester, size: const Size(390, 844));
      await tapRow(tester, 'Computer Science 1');
      expect(find.byKey(const ValueKey('md.sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the full page: Manage with no list behind it', (tester) async {
    window(tester);
    final auth = await start();
    await tester.pumpWidget(hosted(
        auth, layoutHost(const EntityDetailPage(entity: EntityRef(EntityKind.teacher, 101)), scale: 1, scaffold: false)));
    await frames(tester);
    await tapKey(tester, 'md.manage');
    expect(find.byKey(const ValueKey('admin.user_edit')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('layout (320 x 640 · 1400 x 900 · ar / en · text 1.3)', () {
    testWidgets('a teacher, management unfolded at 320 in both languages', (tester) async {
      window(tester, const Size(320, 640));
      final auth = await start();
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        final c = EntityPanelController(rowKind: EntityKind.teacher)..open(const EntityRef(EntityKind.teacher, 101));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(hosted(
            auth, layoutHost(MasterDetailScaffold(controller: c, list: const SizedBox.expand()), scale: 1.3)));
        await frames(tester);
        await tapKey(tester, 'md.manage');
        await tester.ensureVisible(find.byKey(const ValueKey('admin.user_delete')));
        await frames(tester, 4);
        expect(find.byKey(const ValueKey('admin.user_delete')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      AppConfig.lang = 'en';
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a teacher', (tester) async {
      final auth = await start();
      await expectNoLayoutErrors(
        tester,
        () {
          final c = EntityPanelController(rowKind: EntityKind.teacher)..open(const EntityRef(EntityKind.teacher, 101));
          return hosted(auth, MasterDetailScaffold(controller: c, list: const SizedBox.expand()));
        },
        frames: 8,
      );
    });

    testWidgets('the categories page with a category open', (tester) async {
      final auth = await start();
      await expectNoLayoutErrors(tester, () => hosted(auth, const AdminCategoriesPage()), frames: 8);
      final c = EntityPanelController(rowKind: EntityKind.category)..open(const EntityRef(EntityKind.category, 5));
      await expectNoLayoutErrors(
          tester, () => hosted(auth, MasterDetailScaffold(controller: c, list: const SizedBox.expand())), frames: 8);
    });
  });

  testWidgets('a11y: a category detail with its management', (tester) async {
    final auth = await start();
    await expectA11y(tester, 'md category', () {
      final c = EntityPanelController(rowKind: EntityKind.category)..open(const EntityRef(EntityKind.category, 5));
      return MasterDetailScaffold(controller: c, list: const AdminCategoriesPage());
    }, wrap: (app) => hosted(auth, app));
  });
}
