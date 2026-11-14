// Round C item R8: "Recently opened" (AdminRecents), its Overview section and the palette's Recent group and
// "View as a user" command.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/admin/admin_global_search.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminPendingPayoutsProvider;
import 'package:flutter_education_app/features/admin/admin_recents.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_home_layout_test.dart' as base;
import '../layout_harness.dart';

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  late StorageService storage;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  Future<void> boot({String role = 'super-admin', Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': role});
    AdminRecents.instance.resetForTest();
    AppConfig.lang = 'en';
    AppConfig.setDisableList(const []);
  }

  Widget withProviders(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)..loadCachedUser()),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => AdminPendingPayoutsProvider()),
          ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
          ChangeNotifierProvider(create: (_) => ComplaintProvider()),
        ],
        child: child,
      );

  group('AdminRecents', () {
    setUp(() => boot());

    test('newest first, deduplicated, capped at 12', () async {
      final r = AdminRecents.instance;
      await r.use('7');
      for (var i = 0; i < 15; i++) {
        r.record('k$i');
      }
      expect(r.keys.length, AdminRecents.cap);
      expect(r.keys.first, 'k14');
      r.record('k10');
      expect(r.keys.first, 'k10');
      expect(r.keys.where((k) => k == 'k10').length, 1);
    });

    test('persists per user and reloads', () async {
      final r = AdminRecents.instance;
      await r.use('7');
      r.record('a');
      r.record('b');
      await _settle();
      r.resetForTest();
      await r.use('7');
      expect(r.keys, ['b', 'a']);
      r.resetForTest();
      await r.use('8');
      expect(r.keys, isEmpty);
    });

    test('a failing SharedPreferences does not crash', () async {
      SharedPreferences.setMockInitialValues({'admin_recents_7': 'not a list'}); // getStringList throws on a wrong type
      final r = AdminRecents.instance;
      r.resetForTest();
      await r.use('7');
      expect(r.keys, isEmpty);
      r.record('a');
      await _settle();
      expect(r.keys, ['a']);
    });
  });

  group('Overview section', () {

    Widget body() => withProviders(layoutHost(AdminHomeBody(data: AdminHomeData.fromOverview(base.fullPayload()), name: 'A'), scale: 1));

    testWidgets('no history: the section is not drawn', (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(body());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Recently opened'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('history: tiles, newest first; a kill-switched service is hidden; unknown keys skipped', (tester) async {
      await tester.runAsync(boot);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 2400);
      addTearDown(tester.view.reset);
      AdminRecents.instance.record('svc_datacenter');
      AdminRecents.instance.record('apm_title'); // kill switch profile.payment
      AdminRecents.instance.record('no_such_key');
      AdminRecents.instance.record('svc_requirements');
      AppConfig.setDisableList(const ['profile.payment']);
      await tester.pumpWidget(body());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Recently opened'), findsOneWidget);
      final first = tester.getTopLeft(find.text('Notices to acknowledge'));
      final second = tester.getTopLeft(find.text('svc_datacenter'.tr));
      expect(first.dy < second.dy || first.dx < second.dx, isTrue);
      expect(find.text('apm_title'.tr), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lays out at every size with history', (tester) async {
      await tester.runAsync(boot);
      for (final k in ['svc_datacenter', 'svc_requirements', 'apm_title', 'enrollment_requests', 'teachers', 'view_as_user', 'svc_organizations']) {
        AdminRecents.instance.record(k);
      }
      await expectNoLayoutErrors(tester, () => withProviders(AdminHomeBody(data: AdminHomeData.fromOverview(base.fullPayload()), name: 'A')));
    });
  });

  group('Palette', () {
    BuildContext? ctxOf;
    Future<({List<AdminSearchPage> pages, List<AdminSearchPage> recents})> setup(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(withProviders(layoutHost(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }), scale: 1)));
      ctxOf = ctx;
      return adminPaletteSetup(ctx, const []);
    }

    testWidgets('super admin: View as a user command; recents listed on an empty query', (tester) async {
      await tester.runAsync(boot);
      AdminRecents.instance.record('svc_datacenter');
      final s = await setup(tester);
      expect(s.pages.where((p) => p.label == 'View as a user').length, 1);
      // a caller that already lists it: not added twice
      final listed = AdminSearchPage(label: 'View as a user', icon: Icons.home, onOpen: () {});
      expect(adminPaletteSetup(ctxOf!, [listed]).pages.length, 1);
      expect(s.recents.map((p) => p.label), ['svc_datacenter'.tr]);
      final c = AdminSearchController(pages: s.pages, recents: s.recents);
      expect(c.rows.first.title, 'Recent');
      c.setQuery('zzz');
      expect(c.rows.where((r) => r.title == 'Recent'), isEmpty);
      c.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a plain admin has no View as command', (tester) async {
      await tester.runAsync(() => boot(role: 'admin'));
      final s = await setup(tester);
      expect(s.pages.where((p) => p.label == 'View as a user'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the panel draws Recent and lays out everywhere', (tester) async {
      await tester.runAsync(boot);
      AdminRecents.instance.record('svc_datacenter');
      final s = await setup(tester);
      await expectNoLayoutErrors(
          tester,
          () => withProviders(AdminSearchPanel(controller: AdminSearchController(pages: s.pages, recents: s.recents), onSelect: (_) {})));
    });
  });
}
