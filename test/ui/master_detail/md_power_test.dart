// Phase 8 of the master-detail redesign (D-290): search, saved views, bulk actions, exports.
//   pure       the search payload, the list's query on its URL (both ways), the CSV text
//   bulk       ticking teacher's students offers Message; the note goes to /students/message with their ids, once
//   views      the Views sheet lists the server's views, applies one, saves the current query
//   search     the palette waits for 2 letters, groups the hits, ↓ + Enter picks; no overflow at 320 / 1400, ar / en
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_table_export.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_tools.dart';
import 'package:flutter_education_app/design/master_detail/entity_search_palette.dart';
import 'package:flutter_education_app/features/home/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'md_roles_support.dart';

const _wide = Size(1400, 900);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _searchJson = {
  'query': 'no',
  'groups': [
    {
      'kind': 'student',
      'total': 7,
      'items': [
        {'id': 5, 'name': 'Nour Ali', 'username': 'nour', 'image_url': null},
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
    {'kind': 'planet', 'total': 1, 'items': [{'id': 1}]},
  ],
};

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  group('pure', () {
    test('the search payload: groups in order, an unknown kind left out, second lines', () {
      final r = EntitySearchResult.fromJson(_searchJson);
      expect(r.groups.map((g) => g.kind), [EntityKind.student, EntityKind.course]);
      expect(r.groups.first.total, 7);
      expect(r.flat.map((h) => h.ref.toToken()), ['student:5', 'student:6', 'course:9']);
      expect(r.flat.first.sub, '@nour');
      expect(r.flat.last.sub, 'Nadia');
      expect(r.flat.last.ref.name, 'Numbers');
      expect(EntitySearchResult.fromJson(null).isEmpty, isTrue);
    });

    test('a list query on the URL and back', () {
      const base = EntityListQuery(sort: 'activity_desc', size: 20);
      final q = base.copyWith(search: 'sara ali', sort: 'name', filter: {'attention': 'true'});
      final token = entityListToken(q, defaultSort: 'activity_desc');
      expect(token, isNotNull);
      final back = entityQueryFromParams(entityListParams(token), base,
          sorts: const ['activity_desc', 'name'], filterKeys: const {'attention'});
      expect(back!.search, 'sara ali');
      expect(back.sort, 'name');
      expect(back.filter, {'attention': 'true'});
      expect(back.size, 20);
      expect(entityListToken(base, defaultSort: 'activity_desc'), isNull, reason: 'the default writes nothing');
      // a hand-edited link: an unknown sort and filter are ignored, garbage is no error
      expect(
          entityQueryFromParams({'sort': 'evil', 'f.x': '1'}, base, sorts: const ['name'], filterKeys: const {'attention'}),
          isNull);
      expect(entityListParams('%%%'), isEmpty);
    });

    test('CSV: quoted fields, CRLF lines, a formula-looking text neutralised', () {
      const cols = [AppExportColumn('n', 'Name'), AppExportColumn('v', 'Score', type: AppColType.number)];
      final csv = entityCsv(cols, [
        {'n': 'Ali, "the best"', 'v': 9},
        {'n': '=HYPERLINK("x")', 'v': -2},
      ]);
      final lines = csv.split('\r\n');
      expect(lines[0], 'Name,Score');
      expect(lines[1], '"Ali, ""the best""",9');
      expect(lines[2], startsWith('"\'=HYPERLINK'));
      expect(lines[2], endsWith(',-2'));
    });
  });

  testWidgets('bulk: ticked students get one note through /students/message', (t) async {
    final posts = <Map<String, dynamic>>[];
    final api = FakeApi({
      ...roleRoutes(),
      'POST /api/v1/entities/students/message': (o) {
        posts.add(Map<String, dynamic>.from(o.data as Map));
        return {'sent': 2, 'skipped': 0};
      },
    }, latency: const Duration(milliseconds: 5))
      ..install();
    EntitiesApi.instance.invalidate();
    addTearDown(api.uninstall);
    await t.binding.setSurfaceSize(_wide);
    t.view.physicalSize = _wide;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(EntityListPage<PersonRow>(config: teacherStudentsList(21)), scaffold: true));
    await _settle(t);
    final boxes = find.byType(Checkbox);
    expect(boxes, findsWidgets);
    await t.tap(boxes.at(1));
    await t.tap(boxes.at(2));
    await t.pump();
    expect(find.text('md_p8_export_selected'), findsOneWidget);
    await t.tap(find.text('md_p7_message'));
    await _settle(t);
    await t.enterText(find.byKey(const ValueKey('md.message.text')), 'Exam on Sunday');
    await t.tap(find.byKey(const ValueKey('md.message.send')));
    await _settle(t);
    expect(posts, hasLength(1));
    expect((posts.single['ids'] as List), hasLength(2));
    expect(posts.single['text'], 'Exam on Sunday');
  });

  testWidgets('views: list, apply, save the current query', (t) async {
    final saved = <Map<String, dynamic>>[];
    final api = FakeApi({
      ...roleRoutes(),
      'GET /api/v1/entities/views': (o) => {
            'items': [
              {
                'id': 3,
                'list_id': 'teacher_students',
                'name': 'Needs attention',
                'query': {'filter': {'attention': 'true'}},
              },
            ],
          },
      'POST /api/v1/entities/views': (o) {
        final body = Map<String, dynamic>.from(o.data as Map);
        saved.add(body);
        return {'id': 4, 'list_id': body['list_id'], 'name': body['name'], 'query': body['query']};
      },
    }, latency: const Duration(milliseconds: 5))
      ..install();
    EntitiesApi.instance.invalidate();
    addTearDown(api.uninstall);
    await t.binding.setSurfaceSize(_wide);
    t.view.physicalSize = _wide;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(EntityListPage<PersonRow>(config: teacherStudentsList(21)), scaffold: true));
    await _settle(t);

    await t.tap(find.byKey(const ValueKey('teacher_students.views')));
    await _settle(t);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byKey(const ValueKey('md.view.save')), findsNothing, reason: 'nothing to save on the default query');
    await t.tap(find.text('Needs attention'));
    await _settle(t);
    expect(api.calls.last.query['attention'], 'true', reason: 'the view was applied');

    await t.tap(find.byKey(const ValueKey('teacher_students.views')));
    await _settle(t);
    await t.enterText(find.byKey(const ValueKey('md.view.name')), 'Mine');
    await t.tap(find.byKey(const ValueKey('md.view.save')));
    await _settle(t);
    expect(saved.single['list_id'], 'teacher_students');
    expect(saved.single['query'], {
      'sort': 'activity_desc',
      'filter': {'attention': 'true'},
    });
  });

  group('search palette', () {
    Widget panel(ValueChanged<EntityRef> onSelect, List<String> asked) => EntitySearchPanel(
          onSelect: onSelect,
          search: (q) async {
            asked.add(q);
            return EntitySearchResult.fromJson(_searchJson);
          },
        );

    testWidgets('2 letters, grouped hits, ↓ + Enter picks', (t) async {
      final asked = <String>[];
      EntityRef? picked;
      await t.pumpWidget(layoutHost(panel((r) => picked = r, asked), scaffold: true));
      await t.enterText(find.byKey(const ValueKey('md.search.field')), 'n');
      await t.pump(const Duration(milliseconds: 400));
      expect(asked, isEmpty);
      await t.enterText(find.byKey(const ValueKey('md.search.field')), 'no');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(asked, ['no']);
      expect(find.text('Nour Ali'), findsOneWidget);
      expect(find.text('Numbers'), findsOneWidget);
      expect(find.textContaining('md_p8_kind_student'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(picked?.toToken(), 'student:6');
    });

    testWidgets('no overflow', (t) async {
      await expectNoLayoutErrors(t, () => panel((_) {}, []), act: (t) async {
        await t.enterText(find.byKey(const ValueKey('md.search.field')), 'no');
        await t.pump(const Duration(milliseconds: 400));
        await t.pump();
      });
    });
  });
}
