// D-290 phase 4: the student detail over a FakeApi serving the real entity payloads (md_support.dart).
//
//   overview     the sentence, the states, the money; no stat tiles, no second timeline section
//   history      a course row unfolds its facts and timeline (fetched only then), lessons of one sitting fold into one
//                line, the withdrawal's date, reason and text show
//   focus        a student opened from a course: that course's row open, drawn first when it is not on the first page
//   context      a course opened from a student: their place in it and their timeline, loaded
//   full page    `?from=` keeps the context
//   manage       what `can.manage` adds (and that nobody else gets it, nor a call to the admin API); Remove records the
//                reason; Deactivate reloads and tells the list; Delete closes the panel
//   layout       everything open at 320 x 640 and 1400 x 900, ar / en, text 1.3
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_timeline.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/design/master_detail/student_detail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../admin_ds/people_support.dart';
import '../layout_harness.dart';
import 'md_support.dart';

const _sara = EntityRef(EntityKind.student, 100, label: 'سارة أحمد 1');

Widget _panel(EntityPanelController c) => MasterDetailScaffold(controller: c, list: const SizedBox.expand());

Future<void> _settle(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _wide(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Tapping what is off screen in the panel's own scroll.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  late FakeApi api;

  Map<String, dynamic> withCan(Map<String, dynamic> j, {required bool manage}) => j
    ..['can'] = {'manage': manage, 'message': manage, 'see_money': manage}
    ..['sections'] = manage ? ['courses', 'timeline', 'payments', 'subscriptions'] : ['courses', 'timeline'];

  FakeApi serve({bool manage = true, Map<String, FakeHandler> extra = const {}, Object? Function(int courseId)? timelineOf}) => FakeApi({
        ...entityRoutes(),
        ...peopleRoutes(),
        'GET /api/v1/entities/students/*': (o) {
          final r = entitiesHandler(o);
          return o.uri.pathSegments.last == 'students' || int.tryParse(o.uri.pathSegments.last) != null
              ? withCan(Map<String, dynamic>.from(r as Map), manage: manage)
              : r;
        },
        ...extra,
      }, latency: const Duration(milliseconds: 10))
        ..install();

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    EntitiesApi.instance.invalidate();
  });

  tearDown(() => api.uninstall());

  group('overview and history', () {
    testWidgets('the overview tells the student at a glance, without a second timeline section', (tester) async {
      api = serve();
      await _wide(tester);
      await tester.pumpWidget(layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1));
      await _settle(tester);
      expect(find.text('1 of 6 courses completed'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);
      expect(find.textContaining('1350'), findsOneWidget);
      expect(find.text('Courses and history'), findsOneWidget);
      expect(find.text('Activity'), findsNothing); // the old picker + timeline section
      expect(find.text('Nile University'), findsOneWidget);
      expect(find.text(mdCourses[0].$2), findsWidgets); // the rows loaded, not a skeleton
      expect(find.text('Withdrawn'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('History unfolds the facts and the timeline, fetched only then', (tester) async {
      api = serve();
      await _wide(tester);
      await tester.pumpWidget(layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1));
      await _settle(tester);
      expect(api.calls.where((c) => c.path.endsWith('/timeline')), isEmpty);

      await _tap(tester, find.byKey(const ValueKey('md.student.history.40')));
      expect(api.calls.where((c) => c.path.endsWith('/students/100/courses/40/timeline')), hasLength(1));
      expect(find.text('First visit'), findsWidgets); // a fact, and the timeline's line
      expect(find.text('Expected end'), findsOneWidget);
      expect(find.text('Full history'), findsOneWidget);
      expect(find.text('Finished 3 lessons'), findsOneWidget); // one sitting, one line
      expect(find.textContaining('Quiz 2: Functions'), findsOneWidget);
      expect(find.text('Passed'), findsOneWidget);
      expect(find.text('Not passed'), findsOneWidget);
      expect(find.textContaining('Withdrew · Price'), findsOneWidget);
      expect(find.text('“The monthly fee went up after the first term.”'), findsWidgets);

      // folded and opened again: no second fetch
      await _tap(tester, find.byKey(const ValueKey('md.student.history.40')));
      await _tap(tester, find.byKey(const ValueKey('md.student.history.40')));
      expect(api.calls.where((c) => c.path.endsWith('/timeline')), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a withdrawn course shows the date, the reason and the text in its row', (tester) async {
      api = serve();
      await _wide(tester);
      await tester.pumpWidget(layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1));
      await _settle(tester);
      expect(find.textContaining('Withdrew '), findsOneWidget);
      expect(find.textContaining('Reason: Price'), findsOneWidget);
      expect(find.text('“The monthly fee went up after the first term.”'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('groupTimeline folds lessons of one day that follow each other, and nothing else', () {
      EntityTimelineEvent ev(String type, String day) => EntityTimelineEvent(DateTime.utc(2026, 3, 1), type, {'day': day});
      final days = <DateTime, String>{};
      final events = [
        EntityTimelineEvent(DateTime.utc(2026, 3, 4, 10), 'material_completed', const {}),
        EntityTimelineEvent(DateTime.utc(2026, 3, 4, 9), 'material_completed', const {}),
        EntityTimelineEvent(DateTime.utc(2026, 3, 4, 8), 'exam_submitted', const {}),
        EntityTimelineEvent(DateTime.utc(2026, 3, 4, 7), 'material_completed', const {}),
        EntityTimelineEvent(DateTime.utc(2026, 3, 3, 7), 'material_completed', const {}),
        ev('rated', 'x'),
      ];
      final g = groupTimeline(events, dayOf: (d) => days[d] ?? '${d.month}-${d.day}');
      expect([for (final e in g) e.events.length], [2, 1, 1, 1, 1]);
      expect(g.first.isGroup, isTrue);
      expect(g[1].first.type, 'exam_submitted');
    });
  });

  group('connected', () {
    testWidgets('a student opened from a course opens that course, drawn first when it is not on the first page',
        (tester) async {
      // 41 sorts off the first page here: the server only gives it through `course_id`
      api = serve(extra: {
        'GET /api/v1/entities/students/100/courses': (o) {
          if (o.uri.queryParameters.containsKey('course_id')) return entitiesHandler(o);
          return {'items': [{'course': mdCourseRef(2), ...Map<String, dynamic>.from(studentCourses()[2])..remove('course')}], 'total': 6, 'page': 1, 'size': 10, 'pages': 2};
        },
      });
      await _wide(tester);
      final c = EntityPanelController()
        ..open(const EntityRef(EntityKind.course, 41))
        ..push(_sara);
      await tester.pumpWidget(layoutHost(_panel(c), scale: 1));
      await _settle(tester, 20);
      expect(c.focusCourseId, 41);
      expect(api.calls.where((x) => '${x.query['course_id']}' == '41'), hasLength(1));
      expect(find.text(mdCourses[1].$2), findsWidgets);
      // open by itself: its timeline is loaded, the other row's is not
      expect(api.calls.map((x) => x.path), contains('/api/v1/entities/students/100/courses/41/timeline'));
      expect(api.calls.map((x) => x.path), isNot(contains('/api/v1/entities/students/100/courses/42/timeline')));
      expect(find.text('Finished 3 lessons'), findsOneWidget);
      expect(
          tester.getTopLeft(find.text(mdCourses[1].$2).first).dy, lessThan(tester.getTopLeft(find.text(mdCourses[2].$2).first).dy));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a course opened from a student keeps that student, with their timeline loaded', (tester) async {
      api = serve();
      await _wide(tester);
      final c = EntityPanelController(rowKind: EntityKind.student)
        ..open(_sara)
        ..push(const EntityRef(EntityKind.course, 40));
      await tester.pumpWidget(layoutHost(_panel(c), scale: 1));
      await _settle(tester, 20);
      expect(c.contextRef, _sara);
      expect(find.text('In this course'), findsOneWidget);
      expect(find.text('Finished 3 lessons'), findsOneWidget);
      expect(find.byKey(const ValueKey('md.student.context_history')), findsOneWidget);
      // a tap on the student goes back to them through the trail, one link
      await _tap(tester, find.byKey(const ValueKey('md.student.context_history')));
      expect(find.text('Finished 3 lessons'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('a list URL keeps the context: `?open=course:41,student:100`', () {
      expect(EntityLinkRequest.token(_sara, from: const EntityRef(EntityKind.course, 41)), 'course:41,student:100');
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=course:41,student:100');
      expect(EntityLinkRequest.takeFrom, const EntityRef(EntityKind.course, 41));
      expect(EntityLinkRequest.take(), _sara);
      EntityLinkRequest.offer('/admin_dashboard/admin-students?open=student:100');
      expect(EntityLinkRequest.takeFrom, isNull);
      expect(EntityLinkRequest.take(), _sara);
      api = serve(); // tearDown
    });

    testWidgets('the full page keeps the context: `?from=` starts the trail', (tester) async {
      api = serve();
      await _wide(tester);
      expect(EntityNavigator.location(_sara, from: const EntityRef(EntityKind.course, 41)), '/view/student/100?from=course%3A41');
      expect(EntityNavigator.location(_sara), '/view/student/100');
      await tester.pumpWidget(layoutHost(const EntityDetailPage(entity: _sara, from: EntityRef(EntityKind.course, 41)), scale: 1));
      await _settle(tester, 20);
      expect(find.text('Finished 3 lessons'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('manage', () {
    testWidgets('a viewer without can.manage gets no management and no call to the admin API', (tester) async {
      api = serve(manage: false);
      await _wide(tester);
      await tester.pumpWidget(layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1));
      await _settle(tester);
      expect(find.text(mdCourses[0].$2), findsWidgets);
      for (final k in const ['admin.user_edit', 'admin.user_delete', 'md.student.enrol', 'md.student.grant']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      await _tap(tester, find.byKey(const ValueKey('md.student.history.40')));
      expect(find.byKey(const ValueKey('md.student.remove.40')), findsNothing);
      expect(api.calls.where((c) => c.path.startsWith('/api/v1/admin')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a manager gets everything the old sheet held, in the detail', (tester) async {
      api = serve();
      final auth = await peopleSetUp(api);
      await _wide(tester);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1)));
      await _settle(tester);
      for (final k in const [
        'admin.user_edit', 'admin.user_view_as', 'md.student.message', 'md.student.enrol', 'md.student.grant',
        'admin.user_verify', 'admin.user_mfa_reset', 'admin.user_deactivate', 'admin.user_delete',
      ]) {
        expect(find.byKey(ValueKey(k), skipOffstage: false), findsOneWidget, reason: k);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Remove records the reason, then the detail reloads and the list hears of it', (tester) async {
      api = serve(extra: {'DELETE /api/v1/admin/users/100/enrollments/*': (_) => {'dropped': true}});
      final auth = await peopleSetUp(api);
      await _wide(tester);
      var told = 0;
      final c = EntityPanelController()
        ..open(_sara)
        ..onEntityChanged = () => told++;
      await tester.pumpWidget(peopleProviders(auth, layoutHost(_panel(c), scale: 1)));
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('md.student.history.40')));
      await _tap(tester, find.byKey(const ValueKey('md.student.remove.40')));
      await _tap(tester, find.text('No time'));
      await tester.enterText(find.byType(TextField).last, 'moved abroad');
      await _tap(tester, find.byKey(const ValueKey('md.student.remove_confirm')));
      final del = api.calls.singleWhere((x) => x.method == 'DELETE');
      expect(del.path, '/api/v1/admin/users/100/enrollments/40');
      expect(del.query, {'reason_code': 'time', 'reason': 'moved abroad'});
      expect(told, 1);
      expect(api.calls.where((x) => x.path == '/api/v1/entities/students/100'), hasLength(greaterThan(1)));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Deactivate asks first, saves and reloads; Delete closes the panel', (tester) async {
      api = serve();
      final auth = await peopleSetUp(api);
      await _wide(tester);
      final c = EntityPanelController()..open(_sara);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(_panel(c), scale: 1)));
      await _settle(tester);
      await _tap(tester, find.byKey(const ValueKey('admin.user_deactivate')));
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      expect(api.calls.where((x) => x.method == 'PUT' && x.path == '/api/v1/admin/users/100'), hasLength(1));
      await _tap(tester, find.byKey(const ValueKey('admin.user_delete')));
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      expect(api.calls.where((x) => x.method == 'DELETE' && x.path == '/api/v1/admin/users/100'), hasLength(1));
      expect(c.isOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed admin load says so and retries, never a blank', (tester) async {
      var fail = true;
      api = serve(extra: {
        'GET /api/v1/admin/users/*': (o) => fail
            ? const FakeResponse(403, {'detail': {'code': 'forbidden', 'message': 'x'}})
            : userDetail(100, 'student'),
      });
      final auth = await peopleSetUp(api);
      await _wide(tester);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(_panel(EntityPanelController()..open(_sara)), scale: 1)));
      await _settle(tester, 40);
      expect(find.byKey(const ValueKey('admin.user_delete'), skipOffstage: false), findsNothing);
      expect(find.text('admin_could_not_load_data'.tr, skipOffstage: false), findsOneWidget);
      fail = false;
      await _tap(tester, find.text('retry'.tr, skipOffstage: false).last);
      await _settle(tester, 30);
      expect(find.byKey(const ValueKey('admin.user_delete'), skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('layout (320 x 640 · 1400 x 900 · ar / en · text 1.3)', () {
    testWidgets('a manager\'s student with a course open', (tester) async {
      api = serve();
      await expectNoLayoutErrors(tester, () {
        final c = EntityPanelController()
          ..open(const EntityRef(EntityKind.course, 40))
          ..push(_sara);
        return _panel(c);
      }, frames: 10);
    });

    testWidgets('a course opened from a student, and the full page', (tester) async {
      api = serve();
      await expectNoLayoutErrors(tester, () {
        final c = EntityPanelController()
          ..open(_sara)
          ..push(const EntityRef(EntityKind.course, 40));
        return _panel(c);
      }, frames: 10);
      await expectNoLayoutErrors(
          tester, () => const EntityDetailPage(entity: _sara, from: EntityRef(EntityKind.course, 41)), scaffold: false, frames: 10);
    });

    testWidgets('the overview and the facts alone, with no courses and with every state', (tester) async {
      api = serve();
      final empty = EntitySummary.fromJson({
        'kind': 'student',
        'id': 1,
        'stats': {'enrolled': 0, 'avg_progress': 0, 'last_activity_at': null},
      });
      final full = EntitySummary.fromJson(studentSummary(100));
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: Column(children: [
                  StudentOverviewCard(summary: empty),
                  StudentOverviewCard(summary: full),
                ]),
              ));
    });
  });
}
