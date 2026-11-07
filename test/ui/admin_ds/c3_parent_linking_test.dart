// C-round: Parent linking is ONE page (Requests + Settings). Both tabs work, a plain admin has no Settings tab,
// unsaved settings are guarded when switching tabs, Save sends every field the old page sent, no layout error.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_parent_linking_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../layout_harness.dart';
import 'cfg_support.dart';

Map<String, FakeHandler> _routes() => {
      'GET /api/v1/admin/parent-link/requests': (_) => {
            'items': [
              {'id': 1, 'parent_name': 'Parent One', 'student_id': 7, 'student_name': 'Student One', 'status': 'pending', 'mode': 'advanced', 'documents_count': 2, 'created_at': '2026-11-01T10:00:00Z'},
            ],
            'page': 1,
            'pages': 1,
            'pending_count': 1,
          },
      'GET /api/v1/admin/parent-link/settings': (_) => {
            'mode': 'advanced',
            'code_ttl_minutes': 15,
            'advanced': {
              'fields': [
                {'key': 'national_id', 'label_ar': 'الرقم القومي', 'label_en': 'National ID', 'type': 'text', 'required': true},
              ],
              'documents': [
                {'key': 'id_card', 'label_ar': 'بطاقة الهوية', 'label_en': 'ID card', 'required': true},
              ],
            },
            'external': {},
          },
      'PUT /api/v1/admin/parent-link/settings': (o) {
        (cfgSent['PUT settings'] ??= []).add(o.data);
        return o.data;
      },
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  Future<void> open(WidgetTester tester, {String role = 'super-admin', bool settings = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeApi(_routes(), latency: const Duration(milliseconds: 20));
    final auth = await cfgSetUp(api, role: role);
    await tester.pumpWidget(cfgProviders(auth, layoutHost(AdminParentLinkingPage(openSettings: settings), scale: 1, scaffold: false)));
    await cfgPump(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder tab(String label) => find.descendant(of: find.byType(AppTabs), matching: find.text(label));
  Finder ttl() => find.byWidgetPredicate((w) => w is TextField && w.keyboardType == TextInputType.number).first;
  AppButton save(WidgetTester tester) => tester.widget<AppButton>(find.byKey(const ValueKey('admin_parent_linking.save')));

  testWidgets('both tabs: requests first, then the settings form', (tester) async {
    await open(tester);
    expect(find.text('Parent One'), findsWidgets);
    expect(find.text('Student One'), findsWidgets);
    expect(find.byKey(const ValueKey('admin_parent_linking.save')), findsNothing);
    await tester.tap(tab('Settings'));
    await cfgPump(tester, 5);
    expect(find.byKey(const ValueKey('admin_parent_linking.save')), findsOneWidget);
    expect(save(tester).onPressed, isNull, reason: 'clean form: Save is off');
    await close(tester);
  });

  testWidgets('plain admin: requests only, no tab bar', (tester) async {
    await open(tester, role: 'admin');
    expect(find.byType(AppTabs), findsNothing);
    expect(find.text('Parent One'), findsWidgets);
    expect(find.text('Student One'), findsWidgets);
    await close(tester);
  });

  testWidgets('settings: switching tabs with unsaved edits asks; Cancel stays, Discard drops the edit', (tester) async {
    await open(tester, settings: true);
    await tester.enterText(ttl(), '45');
    await cfgPump(tester, 3);
    expect(save(tester).onPressed, isNotNull);
    await tester.tap(tab('Requests'));
    await cfgPump(tester, 3);
    expect(find.text('Discard changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await cfgPump(tester, 3);
    expect(find.byKey(const ValueKey('admin_parent_linking.save')), findsOneWidget, reason: 'still on Settings');
    expect(tester.widget<TextField>(ttl()).controller!.text, '45');

    await tester.tap(tab('Requests'));
    await cfgPump(tester, 3);
    await tester.tap(find.text('Discard changes'));
    await cfgPump(tester, 4);
    expect(find.byKey(const ValueKey('admin_parent_linking.save')), findsNothing);
    await tester.tap(tab('Settings'));
    await cfgPump(tester, 6);
    expect(tester.widget<TextField>(ttl()).controller!.text, '15', reason: 'the discarded edit is gone');
    await close(tester);
  });

  testWidgets('settings: Save sends every field the old page sent', (tester) async {
    await open(tester, settings: true);
    await tester.enterText(ttl(), '45');
    await cfgPump(tester, 3);
    save(tester).onPressed!();
    await cfgPump(tester, 6);
    final body = cfgSent['PUT settings']!.single as Map;
    expect(body.keys.toSet(), {'mode', 'code_ttl_minutes', 'advanced'}, reason: 'no external block while it is unconfigured');
    expect(body['mode'], 'advanced');
    expect(body['code_ttl_minutes'], 45);
    final adv = body['advanced'] as Map;
    expect((adv['fields'] as List).single['key'], 'national_id');
    expect((adv['documents'] as List).single['key'], 'id_card');
    await close(tester);
  });

  testWidgets('layout (super admin, requests tab)', (tester) async {
    final api = FakeApi(_routes(), latency: const Duration(milliseconds: 10));
    final auth = await cfgSetUp(api);
    await expectNoLayoutErrors(tester, () => cfgProviders(auth, const AdminParentLinkingPage()), scaffold: false, frames: 10);
  });

  testWidgets('layout (super admin, settings tab)', (tester) async {
    final api = FakeApi(_routes(), latency: const Duration(milliseconds: 10));
    final auth = await cfgSetUp(api);
    await expectNoLayoutErrors(tester, () => cfgProviders(auth, const AdminParentLinkingPage(openSettings: true)),
        scaffold: false, frames: 10);
  });

  testWidgets('layout (plain admin)', (tester) async {
    final api = FakeApi(_routes(), latency: const Duration(milliseconds: 10));
    final auth = await cfgSetUp(api, role: 'admin');
    await expectNoLayoutErrors(tester, () => cfgProviders(auth, const AdminParentLinkingPage()), scaffold: false, frames: 10);
  });
}
