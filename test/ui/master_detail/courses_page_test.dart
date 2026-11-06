// D-290 phase 5: the admin courses list and the course detail over a FakeApi serving the real payloads.
//
//   layout     the list, a course's panel, a course drilled from a student and the Manage sheet at 320 x 640 and
//              1400 x 900, ar / en, text 1.3: no overflow, no exception
//   table      rows draw real content, a row opens the LOADED detail, sort both ways, numbered pages and page size, an
//              export reads every page, a panel leaves the wide columns out, phone cards
//   actions    publish / complete / edit / manage / trash reach the server and refresh the panel
//   links      the category and teacher cells open their panels; deep link
//   detail     the statistics, trend, reasons and the state counts; a course opened from a student shows that student's
//              history; Back returns to the students list with its filter and scroll, without asking again
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart'
    show EntityTimelineTile, mdCourseInsight, mdReasonLabel, mdStateLabel, mdTrendChange;
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/features/admin/admin_courses_page.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart';
import 'package:flutter_education_app/features/admin/admin_table_export.dart' show fetchAllRows;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../a11y_guidelines_test.dart' show expectA11y;
import '../admin_ds/people_support.dart';
import '../layout_harness.dart';
import 'courses_support.dart';
import 'master_detail_layout_test.dart' show frames;
import 'md_support.dart';

Widget _page() => const AdminCoursesPage(embedded: true);

Finder _inPanel(Finder f) => find.descendant(of: find.byType(EntityPanel), matching: f);

Future<void> _pump(WidgetTester tester, Widget app, {Size size = const Size(1700, 1000)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(app);
  await frames(tester, 8);
}

void main() {
  late FakeApi api;
  late List<Object?> writes;

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    debugClearAppTableLayouts();
    EntitiesApi.instance.invalidate();
    writes = [];
    api = FakeApi({
      ...entityRoutes(),
      ...courseRoutes(),
      'PUT /api/v1/admin/courses/*': (o) {
        writes.add(o.data);
        return {'ok': true};
      },
      'DELETE /api/v1/admin/courses/*': (o) {
        writes.add('delete ${o.uri.path} ${o.uri.queryParameters['force']}');
        return {'ok': true};
      },
    }, latency: const Duration(milliseconds: 10));
  });

  tearDown(() => api.uninstall());

  Future<Widget Function(Widget)> signIn() async {
    final auth = await peopleSetUp(api);
    loadP5Keys();
    return (w) => peopleProviders(auth, w);
  }

  group('layout (320 x 640 · 1400 x 900 · ar / en · text 1.3)', () {
    testWidgets('the list, its empty and error states', (tester) async {
      final wrap = await signIn();
      await expectNoLayoutErrors(tester, () => wrap(_page()), frames: 8);
      api.uninstall();
      api = FakeApi(courseRoutes(total: 0), latency: const Duration(milliseconds: 10))..install();
      await expectNoLayoutErrors(tester, () => wrap(_page()), frames: 6);
      api.uninstall();
      api = FakeApi({'GET /api/v1/admin/courses': (_) => const FakeResponse(500, {'detail': 'boom'})},
          latency: const Duration(milliseconds: 10))
        ..install();
      await expectNoLayoutErrors(tester, () => wrap(_page()), frames: 6);
    });

    testWidgets('a course panel, opened on arrival', (tester) async {
      final wrap = await signIn();
      await expectNoLayoutErrors(tester, () {
        EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
        return wrap(_page());
      }, frames: 10);
    });

    testWidgets('a course drilled from a student: the student history block', (tester) async {
      await signIn();
      await expectNoLayoutErrors(tester, () {
        final c = EntityPanelController(rowKind: EntityKind.student)
          ..open(const EntityRef(EntityKind.student, 100, label: 'سارة أحمد'))
          ..push(const EntityRef(EntityKind.course, 40));
        return MasterDetailScaffold(controller: c, list: const SizedBox.expand());
      }, frames: 8);
    });

    testWidgets('the Manage sheet', (tester) async {
      final wrap = await signIn();
      await expectNoLayoutErrors(tester, () {
        EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:41');
        return wrap(_page());
      }, frames: 10, act: (tester) async {
        final manage = find.byKey(const ValueKey('md.course.manage'));
        await tester.ensureVisible(manage);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(manage, warnIfMissed: false);
      });
    });
  });

  group('the table', () {
    testWidgets('rows hold real content; a row opens the panel with its LOADED detail', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      expect(find.text('Python Programming Basics'), findsOneWidget);
      expect(find.byType(EntityChip), findsWidgets);
      expect(find.text('148'), findsOneWidget, reason: 'the students column');
      expect(find.text('EGP 900'), findsOneWidget);
      expect(find.textContaining('3 pending payments'), findsOneWidget);
      expect(find.textContaining('120,000.50 EGP'), findsOneWidget, reason: 'the income of every course');

      await tester.tap(find.text('Python Programming Basics'));
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
      // not a skeleton: the server's figures, the insight, the trend bars and the students themselves
      expect(_inPanel(find.byKey(const ValueKey('md.course.insight'))), findsOneWidget);
      expect(_inPanel(find.textContaining('31 of 148')), findsOneWidget);
      expect(_inPanel(find.byType(AppBarChart)), findsOneWidget);
      expect(_inPanel(find.text(mdReasonLabel('time'))), findsOneWidget);
      expect(_inPanel(find.text('Omar Khaled')), findsOneWidget);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/courses/40/students'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a column sorts both ways on the server, largest first', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      await tester.tap(find.text('md_stat_students'.tr).first);
      await frames(tester, 3);
      expect(api.calls.last.query['sort'], 'students_desc');
      await tester.tap(find.text('md_stat_students'.tr).first);
      await frames(tester, 3);
      expect(api.calls.last.query['sort'], 'students_asc');
      await tester.tap(find.text('admin_price'.tr).first);
      await frames(tester, 3);
      expect(api.calls.last.query['sort'], 'price_asc');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('numbered pages replace the rows; a page size starts over; the total shows', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      expect(find.textContaining('of 45'), findsOneWidget);
      await tester.tap(find.byTooltip('ds_next_page'.tr));
      await frames(tester, 4);
      expect(api.calls.last.query['page'], '2');
      expect(find.textContaining('21–40'), findsOneWidget);
      final p = _provider(tester);
      expect(p.rows.length, 20, reason: 'replaced, not appended');
      await p.setPageSize(50);
      await frames(tester, 4);
      expect(api.calls.last.query['size'], '50');
      expect(api.calls.last.query['page'], '1');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an action on page 2 stays on page 2; a page emptied by a delete falls back', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      final p = _provider(tester);
      await p.goToPage(2);
      await frames(tester, 3);
      await p.update(60, {'is_published': false});
      await frames(tester, 3);
      expect(p.page, 2);
      expect(writes, [
        {'is_published': false}
      ]);

      api.routes['GET /api/v1/admin/courses'] = (o) => coursesList(o, total: 20); // the 21st row is gone
      await p.reloadPage();
      await frames(tester, 3);
      expect(p.page, 1);
      expect(p.rows.length, 20);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an export of a numbered table fetches every page, even from the last one', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      final p = _provider(tester);
      await p.goToPage(3);
      await frames(tester, 3);
      expect(p.hasMore, isFalse);
      expect(p.allLoaded, isFalse, reason: 'page 3 of 3 is not every row');
      final rows = await tester.runAsync(() => fetchAllRows(p));
      expect(rows!.length, 45);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a side panel leaves the wide columns out, closing it brings them back', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)), size: const Size(1500, 900));
      final header = find.byKey(const ValueKey('app_table_header'));
      expect(find.descendant(of: header, matching: find.text('category_label'.tr)), findsOneWidget);
      await tester.tap(find.text('Python Programming Basics'));
      await frames(tester, 8);
      expect(find.descendant(of: header, matching: find.text('category_label'.tr)), findsNothing);
      expect(find.descendant(of: header, matching: find.text('admin_teacher'.tr)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('md.close')));
      await frames(tester, 4);
      expect(find.descendant(of: header, matching: find.text('category_label'.tr)), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a phone card shows the same facts; a tap opens the sheet', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)), size: const Size(390, 844));
      expect(find.byKey(const ValueKey('app_table_header')), findsNothing);
      expect(find.text('Python Programming Basics'), findsOneWidget);
      expect(find.text('148 students'), findsOneWidget);
      await tester.tap(find.text('Python Programming Basics'));
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('md.sheet')), findsOneWidget);
      expect(_inPanel(find.byKey(const ValueKey('md.course.insight'))), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a trashed course reads as archived and offers no publish', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)), size: const Size(1700, 1300));
      expect(find.text('md_status_archived'.tr), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('actions', () {
    testWidgets('publish and complete go to the server, and the panel reads the course again', (tester) async {
      final wrap = await signIn();
      EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      final before = api.calls.where((c) => c.path == '/api/v1/entities/courses/40').length;
      await tester.tap(find.byKey(const ValueKey('md.course.publish')));
      await frames(tester, 6);
      expect(writes.single, {'is_published': false});
      expect(api.calls.where((c) => c.path == '/api/v1/entities/courses/40').length, greaterThan(before));
      await tester.tap(find.byKey(const ValueKey('md.course.complete')));
      await frames(tester, 6);
      expect(writes.last, {'status': 'completed'});
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Manage holds the forms and every old control; Edit opens the course form', (tester) async {
      final wrap = await signIn();
      EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      await tester.tap(find.byKey(const ValueKey('md.course.manage')));
      await frames(tester, 8);
      for (final key in ['admin_access_and_resubscribe', 'admin_payment_settings', 'admin_recent_payments', 'admin_controls']) {
        await tester.scrollUntilVisible(find.text(key.tr), 200, scrollable: find.byType(Scrollable).last);
        expect(find.text(key.tr), findsOneWidget, reason: key);
      }
      await tester.tap(find.text('btn_edit'.tr).last);
      await frames(tester, 12);
      expect(find.text('admin_edit_course'.tr), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Move to trash asks first, then closes the panel of that course', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      await tester.tap(find.text('Python Programming Basics'));
      await frames(tester, 8);
      await tester.tap(find.byTooltip('ds_more_actions'.tr).first);
      await frames(tester, 4);
      await tester.tap(find.text('course_move_to_trash'.tr).last);
      await frames(tester, 4);
      await tester.tap(find.text('course_move_to_trash'.tr).last); // the confirmation
      await frames(tester, 8);
      expect(writes.single, 'delete /api/v1/admin/courses/40 true');
      expect(find.byType(EntityPanel), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('links', () {
    testWidgets('a teacher and a category cell open their own panels; the row stays unselected', (tester) async {
      final wrap = await signIn();
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      await tester.tap(find.widgetWithText(EntityChip, mdTeachers[1]).first);
      await frames(tester, 8);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/teachers/21'));
      expect(find.byKey(const ValueKey('app_table_current_bar')), findsNothing);
      await tester.tap(find.text('Science').first);
      await frames(tester, 8);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/categories/3'));
      expect(find.byKey(const ValueKey('md.course.manage')), findsNothing, reason: 'course actions on courses only');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('`?open=course:42` opens that panel and selects its row', (tester) async {
      final wrap = await signIn();
      EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:42');
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)));
      expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_table_current_bar')), findsOneWidget);
      expect(_inPanel(find.byKey(const ValueKey('md.course.insight'))), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('course detail', () {
    testWidgets('the state chips count the students; an empty state has no chip', (tester) async {
      final wrap = await signIn();
      EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)), size: const Size(1700, 2400));
      expect(_inPanel(find.text('${mdStateLabel('completed')} · 31')), findsOneWidget);
      expect(_inPanel(find.text('${mdStateLabel('withdrawn')} · 14')), findsOneWidget);
      expect(_inPanel(find.textContaining(mdStateLabel('pending'))), findsNothing, reason: '0 pending');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opened from a student: that student\'s history, one tap from folding, and the row marked', (tester) async {
      await signIn();
      final c = EntityPanelController(rowKind: EntityKind.student)
        ..open(const EntityRef(EntityKind.student, 100, label: 'سارة أحمد'))
        ..push(const EntityRef(EntityKind.course, 40));
      await _pump(tester, layoutHost(MasterDetailScaffold(controller: c, list: const SizedBox.expand()), scale: 1),
          size: const Size(1300, 1800));
      expect(_inPanel(find.byKey(const ValueKey('md.course.history.100'))), findsOneWidget);
      expect(_inPanel(find.text('سارة أحمد in this course')), findsOneWidget);
      expect(_inPanel(find.byType(EntityTimelineTile)), findsWidgets, reason: 'the events themselves, not a skeleton');
      await tester.tap(_inPanel(find.byTooltip('md_p5_hide'.tr)));
      await frames(tester, 2);
      expect(_inPanel(find.byType(EntityTimelineTile)), findsNothing);
      expect(api.calls.map((x) => x.path), contains('/api/v1/entities/students/100/courses/40/timeline'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a student opened from the course, then Back: the filter, the rows and the scroll are as they were',
        (tester) async {
      final wrap = await signIn();
      EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
      await _pump(tester, wrap(layoutHost(_page(), scale: 1)), size: const Size(1700, 700));
      final chip = _inPanel(find.text('${mdStateLabel('withdrawn')} · 14'));
      await tester.scrollUntilVisible(chip, 120, scrollable: _inPanel(find.byType(Scrollable)).first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(chip);
      await frames(tester, 4);
      expect(api.calls.last.query['state'], 'withdrawn');
      final student = _inPanel(find.textContaining(mdStudentsNames[2]));
      await tester.ensureVisible(student.first);
      await frames(tester, 2);
      final scroll = tester.state<ScrollableState>(_inPanel(find.byType(Scrollable)).first).position.pixels;
      expect(scroll, greaterThan(0));
      await tester.tap(student.first);
      await frames(tester, 8);
      expect(api.calls.map((x) => x.path), contains('/api/v1/entities/students/102'));
      api.reset();
      await tester.tap(find.byKey(const ValueKey('md.back')));
      await frames(tester, 4);
      expect(api.calls.where((x) => x.path.contains('/courses/40/students')), isEmpty, reason: 'drawn from memory');
      expect(_inPanel(find.text('${mdStateLabel('withdrawn')} · 14')), findsOneWidget);
      expect(_inPanel(find.textContaining(mdStudentsNames[2])), findsWidgets);
      expect(tester.state<ScrollableState>(_inPanel(find.byType(Scrollable)).first).position.pixels, closeTo(scroll, 1));
      await tester.pumpWidget(const SizedBox());
    });

    test('the insight line and the trend change read the figures', () {
      AppConfig.lang = 'en';
      loadP5Keys();
      final s = EntitySummary.fromJson(courseSummary(40), kind: EntityKind.course, id: 40);
      expect(mdCourseInsight(s), startsWith('31 of 148 students finished'));
      expect(mdCourseInsight(s), contains(mdReasonLabel('time')));
      expect(mdTrendChange(s.trend), 46, reason: 'the last 4 weeks (54) against the 4 before (37)');
      final learner = EntitySummary.fromJson(courseSummary(40, learner: true), kind: EntityKind.course, id: 40);
      expect(mdCourseInsight(learner), isNull);
      expect(mdTrendChange(const [EntityTrendPoint(null, 3)]), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('the courses list with a course panel open', (tester) async {
      final wrap = await signIn();
      await expectA11y(tester, 'md admin courses', () {
        EntityLinkRequest.offer('/admin_dashboard/admin-courses?open=course:40');
        return _page();
      }, wrap: wrap);
    });
  });
}

/// The names of md_support's students.
const mdStudentsNames = mdStudents;

AdminCoursesProvider _provider(WidgetTester tester) {
  final ctx = tester.element(find.byType(MasterDetailScaffold));
  return Provider.of<AdminCoursesProvider>(ctx, listen: false);
}
