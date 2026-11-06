// D-290 phase 3: the master-detail kit over a FakeApi serving the real entity payloads (md_support.dart).
//
//   layout     the scaffold with an open panel (student, course, teacher, category; a drilled trail) and the full page
//              at 320 x 640 and 1400 x 900, ar / en, text 1.3: no overflow, no exception
//   adaptive   inline panel >= 1000, overlay 700 – 999, bottom sheet < 700 (measured on the scaffold's own width)
//   keyboard   ↓ moves to the next row with the panel open, Esc closes, Alt+← walks the trail back
//   back       the system Back closes the panel first (a local history entry; a shell tab honours it)
//   route      `/view/student/12` is the full page (registry, URL entry, the navigator's location, the page itself)
//   admin      the Students list: a row opens the panel, a teacher's Manage quick action opens the control sheet, `?open=` opens a
//              panel on arrival
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellTabs;
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../admin_ds/people_support.dart';
import '../layout_harness.dart';
import 'md_support.dart';

const _rows = [
  EntityRef(EntityKind.student, 100, label: 'سارة أحمد 1'),
  EntityRef(EntityKind.student, 101, label: 'Omar Khaled 2'),
  EntityRef(EntityKind.student, 102, label: 'ليلى محمود 3'),
];

/// A list of [_rows] in a scaffold whose panel shows [open] (and, drilled from it, [push]).
Widget scaffoldWith(EntityRef open, {List<EntityRef> push = const [], EntityPanelController? controller}) {
  final c = controller ?? EntityPanelController(rowKind: EntityKind.student);
  c.siblings = _rows;
  c.open(open);
  for (final p in push) {
    c.push(p);
  }
  return MasterDetailScaffold(
    controller: c,
    rootLabel: 'Students',
    list: ListView(children: [
      for (final r in _rows) ListTile(title: Text(r.name), onTap: () => c.open(r)),
    ]),
  );
}

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

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    EntitiesApi.instance.invalidate();
    api = FakeApi({...entityRoutes(), ...peopleRoutes()}, latency: const Duration(milliseconds: 10))..install();
  });

  tearDown(() => api.uninstall());

  group('layout (320 x 640 · 1400 x 900 · ar / en · text 1.3)', () {
    testWidgets('a student panel', (tester) async {
      await expectNoLayoutErrors(tester, () => scaffoldWith(const EntityRef(EntityKind.student, 100)), frames: 8);
    });

    testWidgets('a course opened from a student (breadcrumbs, the student in context)', (tester) async {
      await expectNoLayoutErrors(
          tester, () => scaffoldWith(_rows.first, push: const [EntityRef(EntityKind.course, 40)]), frames: 8);
    });

    testWidgets('a teacher and a category', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => scaffoldWith(_rows.first,
              push: const [EntityRef(EntityKind.course, 40), EntityRef(EntityKind.teacher, 20)]),
          frames: 8);
      await expectNoLayoutErrors(
          tester, () => scaffoldWith(const EntityRef(EntityKind.category, 5)), frames: 8);
    });

    testWidgets('an error with Retry, then the full page', (tester) async {
      await expectNoLayoutErrors(tester, () => scaffoldWith(const EntityRef(EntityKind.student, 100)), frames: 8);
      api.uninstall();
      api = FakeApi({'GET /api/v1/entities/*': (_) => const FakeResponse(404, {'detail': {'code': 'not_found', 'message': 'x'}})},
          latency: const Duration(milliseconds: 10))
        ..install();
      EntitiesApi.instance.invalidate();
      await expectNoLayoutErrors(tester, () => scaffoldWith(const EntityRef(EntityKind.student, 101)), frames: 8);
      api.uninstall();
      api = FakeApi(entityRoutes(), latency: const Duration(milliseconds: 10))..install();
      await expectNoLayoutErrors(
          tester, () => const EntityDetailPage(entity: EntityRef(EntityKind.course, 41)), scaffold: false, frames: 8);
    });
  });

  group('adaptive', () {
    for (final (w, key) in const [(1200.0, 'md.inline'), (1000.0, 'md.inline'), (850.0, 'md.overlay'), (700.0, 'md.overlay'), (420.0, 'md.sheet')]) {
      testWidgets('${w.toInt()} px → $key', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 800);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first), scale: 1));
        await frames(tester);
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        for (final other in const ['md.inline', 'md.overlay', 'md.sheet'].where((k) => k != key)) {
          expect(find.byKey(ValueKey(other)), findsNothing);
        }
        expect(MasterDetailScaffold.modeFor(w).name, key.substring(3));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('the inline panel sits at the END side (left in Arabic) and its width is remembered', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      for (final lang in const ['en', 'ar']) {
        AppConfig.lang = lang;
        await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first), scale: 1));
        await frames(tester, 4);
        final r = tester.getRect(find.byKey(const ValueKey('md.inline')));
        if (lang == 'en') {
          expect(r.right, 1400);
        } else {
          expect(r.left, 0);
        }
      }
      AppConfig.lang = 'en';
      await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first), scale: 1));
      await frames(tester, 4);
      final before = tester.getRect(find.byKey(const ValueKey('md.inline'))).width;
      await tester.drag(find.byKey(const ValueKey('md.resize')), const Offset(-120, 0));
      await frames(tester, 2);
      final after = tester.getRect(find.byKey(const ValueKey('md.inline'))).width;
      expect(after, greaterThan(before + 60));
      expect((await SharedPreferences.getInstance()).getDouble(MasterDetailScaffold.widthPrefKey), closeTo(after, 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('keyboard, Back, previous / next', () {
    testWidgets('↓ opens the next row, Alt+← walks back, Esc closes', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 800);
      addTearDown(tester.view.resetPhysicalSize);
      final c = EntityPanelController(rowKind: EntityKind.student);
      await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first, controller: c), scale: 1));
      await frames(tester, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await frames(tester, 2);
      expect(c.current, _rows[1]);
      expect(c.selectedId, 101);
      c.push(const EntityRef(EntityKind.course, 40));
      await frames(tester, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await frames(tester, 2);
      expect(c.current, _rows[1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester, 2);
      expect(c.isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the chrome: next / previous / breadcrumbs / close', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 800);
      addTearDown(tester.view.resetPhysicalSize);
      final c = EntityPanelController(rowKind: EntityKind.student);
      await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first, controller: c), scale: 1));
      await frames(tester, 4);
      await tester.tap(find.byKey(const ValueKey('md.next')));
      await frames(tester, 2);
      expect(c.current, _rows[1]);
      await tester.tap(find.byKey(const ValueKey('md.previous')));
      await frames(tester, 2);
      expect(c.current, _rows[0]);
      c.push(const EntityRef(EntityKind.course, 40));
      await frames(tester, 4);
      expect(find.text('Python Programming Basics'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('md.back')));
      await frames(tester, 2);
      expect(c.current, _rows[0]);
      await tester.tap(find.byKey(const ValueKey('md.forward')));
      await frames(tester, 2);
      expect(c.current, const EntityRef(EntityKind.course, 40));
      await tester.tap(find.byKey(const ValueKey('md.close')));
      await frames(tester, 2);
      expect(c.isOpen, isFalse);
      expect(find.byType(EntityPanel), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a link inside the panel drills in (student → course)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      final c = EntityPanelController(rowKind: EntityKind.student);
      await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first, controller: c), scale: 1));
      await frames(tester, 8);
      await tester.tap(find.text('Python Programming Basics').first);
      await frames(tester, 6);
      expect(c.current, const EntityRef(EntityKind.course, 40));
      expect(c.trail.length, 2);
      expect(c.contextStudentId, 100);
      expect(api.calls.map((x) => x.path), contains('/api/v1/entities/courses/40'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the system Back closes the panel first; a shell tab counts it as something to go back from',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 800);
      addTearDown(tester.view.resetPhysicalSize);
      final c = EntityPanelController(rowKind: EntityKind.student);
      await tester.pumpWidget(layoutHost(scaffoldWith(_rows.first, controller: c), scale: 1));
      await frames(tester, 4);
      final route = ModalRoute.of(tester.element(find.byType(MasterDetailScaffold)))!;
      expect(route.willHandlePopInternally, isTrue);
      final tab = ShellTabs().tab('students');
      tab.routes.add(route);
      expect(tab.canPop, isTrue, reason: 'a shell tab with an open panel: Back goes to the tab (closes the panel)');
      await tester.binding.handlePopRoute();
      await frames(tester, 2);
      expect(c.isOpen, isFalse);
      expect(find.byType(MasterDetailScaffold), findsOneWidget, reason: 'the page stays');
      expect(route.willHandlePopInternally, isFalse);
      expect(tab.canPop, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the full page', () {
    test('`/view/student/12` is the registry page entity.view, opened by URL over the home', () {
      final m = AppRoutes.match('/view/student/12')!;
      expect(m.id, 'entity.view');
      expect(m.params, {'kind': 'student', 'id': '12'});
      expect(EntityKind.tryParse(m.params['kind']), EntityKind.student);
      expect(m.intParam('id'), 12);
      expect(EntityNavigator.location(const EntityRef(EntityKind.student, 12)), '/view/student/12');
      expect(AppRoutes.locationOf('/view/student/12', null), '/view/student/12');
      final entry = resolveWebEntry('/view/student/12', signedIn: true, home: '/admin_dashboard', isLink: (_) => false)!;
      expect(entry.route, '/view/student/12');
      expect(entry.overHome, isTrue);
      expect(needsSignInFirst('/view/course/3'), isTrue);
    });

    testWidgets('the page draws the student and its sections', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1600);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(const EntityDetailPage(entity: EntityRef(EntityKind.student, 12)), scale: 1, scaffold: false));
      await frames(tester, 8);
      expect(find.text('سارة أحمد 1'), findsWidgets);
      expect(find.text('md_p4_sec_courses'.tr), findsWidgets);
      expect(find.text('md_sec_payments'.tr), findsOneWidget);
      expect(find.byKey(const ValueKey('md.close')), findsNothing, reason: 'a page has Back, not Close');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('admin Students list', () {
    testWidgets('`?open=student:103` opens that panel on arrival; a phone row tap opens the sheet', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetPhysicalSize);
      final auth = await peopleSetUp(api);
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:103');
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminUsersPage(role: 'student', embedded: true), scale: 1)));
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/students/103'));
      await tester.pumpWidget(const SizedBox());

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminUsersPage(role: 'student', embedded: true), scale: 1)));
      await frames(tester, 10);
      await tester.tap(find.text('Omar Khaled 2').first);
      await frames(tester, 10);
      expect(find.byKey(const ValueKey('md.sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
