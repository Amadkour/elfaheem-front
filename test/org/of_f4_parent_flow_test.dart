// Agent f4: the parent organization view over the fake backend (C2) — a parent with two children, one of them in an
// organization, sees ONE card; the organization page loads; a failure shows Retry and Retry recovers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

const _children = {
  'children': [
    {
      'student': {'id': 1, 'name': 'Sara'},
      'orgs': [
        {'id': 9, 'name_ar': 'جامعة النور', 'name_en': 'Noor University', 'role': 'student', 'status': 'active'}
      ]
    },
    {'student': {'id': 2, 'name': 'Omar'}, 'orgs': []},
  ]
};

const _view = {
  'org': {'id': 9, 'name_ar': 'جامعة النور', 'name_en': 'Noor University', 'timezone': 'Africa/Cairo'},
  'student': {'id': 1, 'name': 'Sara'},
  'today': [
    {'title': 'Algebra', 'course_name': 'Math', 'starts_at': '2026-11-04T08:00:00', 'ends_at': '2026-11-04T09:30:00', 'room': 'B1', 'mode': 'in_person', 'status': 'changed'},
  ],
  'week': [
    {'title': 'Physics', 'course_name': 'Physics', 'starts_at': '2026-11-05T10:00:00', 'ends_at': '2026-11-05T11:00:00', 'room': '', 'mode': 'in_person', 'status': 'cancelled'},
  ],
  'announcements': [
    {'id': 3, 'title': 'School trip', 'body': 'On Friday', 'published_at': '2026-11-03T10:00:00'}
  ],
  'grades': [],
  'attendance': null,
};

Widget _host(Widget child) => ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

Widget _screen() => MaterialApp(
      home: ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: const ParentOrgScreen(studentId: 1, studentName: 'Sara', org: ParentOrgRef(id: 9, nameEn: 'Noor University')),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeApi api;
  var childrenFails = 0;
  var viewFails = 0;

  setUp(() {
    AppConfig.lang = 'en';
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    childrenFails = 0;
    viewFails = 0;
    mockRequestPlugins();
    api = FakeApi({
      'GET /api/v1/org/parent/children': (_) => childrenFails-- > 0 ? throw StateError('boom') : _children,
      'GET /api/v1/org/parent/children/1/orgs/9': (_) => viewFails-- > 0 ? throw StateError('boom') : _view,
    })
      ..install();
  });
  tearDown(() => api.uninstall());

  testWidgets('two children, one in an organization: one card, only that child', (tester) async {
    await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
    await _settle(tester);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Omar'), findsNothing);
    expect(find.text('Noor University'), findsOneWidget);
    expect(api.calls.where((c) => c.path == '/api/v1/org/parent/children').length, 1);
  });

  testWidgets('a parent whose children are in no organization sees nothing', (tester) async {
    api.routes['GET /api/v1/org/parent/children'] = (_) => {'children': []};
    await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
    await _settle(tester);
    expect(find.byType(ParentOrgChildrenList), findsNothing);
    expect(find.text('Sara'), findsNothing);
  });

  testWidgets('the list failed: a compact Retry; Retry loads it', (tester) async {
    childrenFails = 1;
    await tester.pumpWidget(_host(const ParentOrgChildrenCard()));
    await _settle(tester);
    expect(find.text('Sara'), findsNothing);
    final retry = find.text('Retry');
    expect(retry, findsWidgets, reason: 'a Retry action is on screen');
    await tester.tap(retry.first);
    await _settle(tester);
    expect(find.text('Sara'), findsOneWidget);
  });

  testWidgets('the organization page shows today, the week, news and explains the empty blocks', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen());
    await _settle(tester);
    expect(find.text('Noor University'), findsWidgets);
    expect(find.text('Algebra'), findsOneWidget);
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('School trip'), findsOneWidget);
    expect(find.text('No published grades'), findsOneWidget);
    expect(find.text('No attendance recorded yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the organization page failed: Retry, then the data', (tester) async {
    viewFails = 1;
    await tester.pumpWidget(_screen());
    await _settle(tester);
    expect(find.text('Algebra'), findsNothing);
    await tester.tap(find.text('Retry').first);
    await _settle(tester);
    expect(find.text('Algebra'), findsOneWidget);
  });
}
