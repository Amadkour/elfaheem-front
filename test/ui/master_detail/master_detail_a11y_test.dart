// D-290: Flutter's accessibility guidelines (tap targets 48 / 44, labelled tap targets, WCAG text contrast) over the
// detail panel and the admin Students page with a panel open — the same harness as test/ui/a11y_guidelines_test.dart
// (phone + wide, ar / en, light / dark), over the FakeApi entity payloads. Phase 8 parts too: the saved views sheet,
// the search palette with hits, a table with rows ticked and its bulk bar.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_search_palette.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_education_app/features/home/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../a11y_guidelines_test.dart' show expectA11y;
import '../admin_ds/people_support.dart';
import 'master_detail_layout_test.dart' show scaffoldWith;
import 'md_roles_support.dart';
import 'md_support.dart';

const _views = {
  'items': [
    {
      'id': 3,
      'list_id': 'teacher_students',
      'name': 'Needs attention',
      'query': {
        'search': 'sara',
        'filter': {'attention': 'true'},
      },
    },
    {'id': 4, 'list_id': 'teacher_students', 'name': 'كل الطلاب', 'query': <String, dynamic>{}},
  ],
};

const _searchJson = {
  'query': 'no',
  'groups': [
    {
      'kind': 'student',
      'total': 7,
      'items': [
        {'id': 5, 'name': 'نور علي', 'username': 'nour', 'image_url': null},
        {'id': 6, 'name': 'Noha Sami', 'username': null, 'image_url': null},
      ],
    },
    {
      'kind': 'course',
      'total': 1,
      'items': [
        {'id': 9, 'name_ar': 'الأعداد', 'name_en': 'Numbers', 'image_url': null, 'teacher_name': 'Nadia'},
      ],
    },
  ],
};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeApi api;

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    EntitiesApi.instance.invalidate();
    api = FakeApi({...entityRoutes(), ...peopleRoutes()}, latency: const Duration(milliseconds: 10))..install();
  });

  tearDown(() => api.uninstall());

  testWidgets('the detail panel (a student, then a course drilled from it)', (tester) async {
    await expectA11y(tester, 'md panel', () => scaffoldWith(const EntityRef(EntityKind.student, 100)));
    await expectA11y(tester, 'md panel course',
        () => scaffoldWith(const EntityRef(EntityKind.student, 100), push: const [EntityRef(EntityKind.course, 40)]));
  });

  testWidgets('the admin Students page with a student panel open', (tester) async {
    final auth = await peopleSetUp(api);
    await expectA11y(tester, 'md admin students', () {
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:100');
      return const AdminUsersPage(role: 'student', embedded: true);
    }, wrap: (app) => peopleProviders(auth, app));
  });

  group('phase 8', () {
    setUp(() {
      api.uninstall();
      api = FakeApi({
        ...roleRoutes(),
        'GET /api/v1/entities/views': (o) => _views,
      }, latency: const Duration(milliseconds: 10))
        ..install();
    });

    testWidgets('the saved views sheet', (tester) async {
      await expectA11y(tester, 'md views sheet', () => EntityListPage<PersonRow>(config: teacherStudentsList(21)),
          act: (t) async {
        await t.tap(find.byKey(const ValueKey('teacher_students.views')));
        await _settle(t);
        expect(find.byKey(const ValueKey('md.view.3')), findsOneWidget);
      });
    });

    testWidgets('a table with rows ticked: the bulk bar', (tester) async {
      await expectA11y(tester, 'md bulk bar', () => EntityListPage<PersonRow>(config: teacherStudentsList(21)),
          act: (t) async {
        final boxes = find.byType(Checkbox);
        if (boxes.evaluate().length < 3) return; // a phone draws cards (no checkboxes)
        await t.tap(boxes.at(1));
        await t.tap(boxes.at(2));
        await _settle(t);
        expect(find.text('md_p8_export_selected'.tr), findsOneWidget);
      });
    });

    testWidgets('the search palette with hits', (tester) async {
      await expectA11y(
          tester,
          'md search palette',
          () => EntitySearchPanel(
              onSelect: (_) {}, search: (q) async => EntitySearchResult.fromJson(_searchJson)), act: (t) async {
        await t.enterText(find.byKey(const ValueKey('md.search.field')), 'no');
        await t.pump(entitySearchDebounce);
        await _settle(t);
        expect(find.text('Noha Sami'), findsOneWidget);
      });
    });
  });
}
