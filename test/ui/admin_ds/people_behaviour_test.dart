// Behaviour of the people pages: money formatting, the Students table (rows, infinite scroll, ONE primary action, no
// floating button, registered refresh), the user detail sheet (Activate is not red, Delete names the user, no "null",
// translated codes, showAdminUserDetail by id), the Admins provider (a mid-load search does not kill pagination, a
// failed refresh keeps the rows), View as (no stray arrow, role tabs), My account (leaving mid-load is safe).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_education_app/features/admin/admin_admins_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/admin/admin_profile_page.dart';
import 'package:flutter_education_app/features/admin/admin_users_page.dart';
import 'package:flutter_education_app/features/admin/admin_view_as_page.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_api.dart';
import '../master_detail/md_support.dart' show entityRoutes;
import '../layout_harness.dart';
import 'people_support.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  Future<void> bigView(WidgetTester tester, [Size size = const Size(1400, 1000)]) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  test('money(): thousands separators with Latin digits, decimals only when needed, currency after', () {
    expect(money(0), '0');
    expect(money(999), '999');
    expect(money(12480), '12,480');
    expect(money(1234567.5), '1,234,567.50');
    expect(money(1234.5, 'EGP'), '1,234.50 EGP');
    expect(money(-1234567), '-1,234,567');
    expect(money(0.5), '0.50');
    expect(money(1000, ''), '1,000');
    expect(kSearchDelay, const Duration(milliseconds: 400));
  });

  group('Students tab', () {
    testWidgets('a real table with infinite scroll, ONE primary action, no floating button, a registered refresh', (tester) async {
      await bigView(tester);
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      final slot = AdminRefreshSlot();
      await tester.pumpWidget(peopleProviders(
        auth,
        layoutHost(AdminRefreshScope(slot: slot, child: const AdminUsersPage(role: 'student', embedded: true)), scale: 1),
      ));
      await pumpFrames(tester);

      expect(find.byWidgetPredicate((w) => w is AppDataTable), findsOneWidget);
      expect(find.text('Omar Khaled 2'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      // exactly one gradient (primary) button: the Add action
      final primaries = tester.widgetList<AppButton>(find.byType(AppButton)).where((b) => b.variant == AppButtonVariant.primary);
      expect(primaries.length, 1);
      expect(primaries.single.label, 'admin_add_student'.tr);
      // the shell's Refresh reloads this page in place
      expect(slot.reload, isNotNull);
      // the first page only so far
      expect(api.calls.where((c) => c.path == '/api/v1/admin/users').map((c) => c.query['page']).first, '1');

      // scrolling to the end asks for page 2
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
      await pumpFrames(tester);
      expect(api.calls.where((c) => c.path == '/api/v1/admin/users').map((c) => c.query['page']), contains('2'));

      // Refresh keeps working through the slot (page 1 again)
      api.reset();
      unawaited(slot.reload!());
      await pumpFrames(tester);
      expect(api.calls.where((c) => c.path == '/api/v1/admin/users').map((c) => c.query['page']).first, '1');
      await close(tester);
    });

    testWidgets('one status filter: the old chip rows are gone', (tester) async {
      await bigView(tester);
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminUsersPage(role: 'student', embedded: true), scale: 1)));
      await pumpFrames(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('admin_filter_status'.tr), findsWidgets);
      await close(tester);
    });

    testWidgets('a row opens the detail panel (D-290), its Manage opens the detail sheet; View as is a row action',
        (tester) async {
      await bigView(tester);
      EntitiesApi.instance.invalidate();
      final api = FakeApi({...peopleRoutes(), ...entityRoutes()}, latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminUsersPage(role: 'student', embedded: true), scale: 1)));
      await pumpFrames(tester);
      expect(find.byIcon(Icons.visibility_rounded), findsWidgets);
      await tester.tap(find.text('سارة أحمد 1').first);
      await pumpFrames(tester);
      expect(api.calls.map((c) => c.path), contains('/api/v1/entities/students/100'));
      await tester.tap(find.byKey(const ValueKey('md.manage')));
      await pumpFrames(tester);
      expect(api.calls.map((c) => c.path), contains('/api/v1/admin/users/100'));
      await close(tester);
    });
  });

  group('user detail sheet', () {
    Future<void> openDetail(WidgetTester tester, FakeApi api, {required int id, required String role}) async {
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(
        auth,
        layoutHost(Builder(builder: (c) => TextButton(onPressed: () => showAdminUserDetail(c, userId: id, role: role), child: const Text('open'))), scale: 1),
      ));
      await tester.tap(find.text('open'));
      await pumpFrames(tester);
    }

    AppButton button(WidgetTester tester, String key) => tester.widget<AppButton>(find.byKey(ValueKey(key)));

    testWidgets('Activate is not red; only Deactivate and Delete are danger', (tester) async {
      await bigView(tester, const Size(900, 1800));
      await openDetail(tester, FakeApi(peopleRoutes(detailActive: false), latency: const Duration(milliseconds: 50)), id: 100, role: 'student');
      expect(find.byKey(const ValueKey('admin.user_activate')), findsOneWidget);
      expect(button(tester, 'admin.user_activate').variant, isNot(AppButtonVariant.danger));
      expect(find.byKey(const ValueKey('admin.user_deactivate')), findsNothing);
      expect(button(tester, 'admin.user_delete').variant, AppButtonVariant.danger);
      expect(button(tester, 'admin.user_delete').dangerOutline, isTrue);
      await close(tester);
    });

    testWidgets('an active user shows Deactivate as a danger action', (tester) async {
      await bigView(tester, const Size(900, 1800));
      await openDetail(tester, FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50)), id: 100, role: 'student');
      expect(find.byKey(const ValueKey('admin.user_activate')), findsNothing);
      expect(button(tester, 'admin.user_deactivate').variant, AppButtonVariant.danger);
      // View as and Edit sit in the first row, before the danger zone
      expect(find.byKey(const ValueKey('admin.user_view_as')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin.user_edit')), findsOneWidget);
      await close(tester);
    });

    testWidgets('Delete asks first and names the user', (tester) async {
      await bigView(tester, const Size(900, 1800));
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50));
      await openDetail(tester, api, id: 100, role: 'student');
      await tester.tap(find.byKey(const ValueKey('admin.user_delete')));
      await pumpFrames(tester, 5);
      expect(find.textContaining('سارة أحمد 1'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('سارة أحمد 1')), findsOneWidget);
      await tester.tap(find.text('exam_cancel'.tr));
      await pumpFrames(tester, 5);
      expect(api.calls.where((c) => c.method == 'DELETE'), isEmpty);
      await close(tester);
    });

    testWidgets('a teacher without experience shows a dash, not "null"; codes are translated; courses use countText',
        (tester) async {
      await bigView(tester, const Size(900, 1800));
      await openDetail(tester, FakeApi(peopleRoutes(detailRole: 'teacher'), latency: const Duration(milliseconds: 50)), id: 103, role: 'teacher');
      expect(find.text('null'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('Live and recorded'), findsOneWidget); // teaching_type: both
      expect(find.text('Paid'), findsOneWidget); // payment_type: paid
      expect(find.text('both'), findsNothing);
      expect(find.text('3 courses'), findsOneWidget); // courses_count from the row, with the plural form
      await close(tester);
    });

    testWidgets('closing the sheet while a request is running does not throw', (tester) async {
      await bigView(tester, const Size(900, 1800));
      await openDetail(tester, FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 400)), id: 100, role: 'student');
      // the sheet is still loading: close it and let the answer land
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('Admins', () {
    testWidgets('a search that changes mid-load does not leave loadingMore stuck (pagination keeps working)', (tester) async {
      await tester.runAsync(() async {
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 100));
      await peopleSetUp(api);
      final p = AdminAdminsProvider();
      await p.refresh();
      expect(p.items.length, 20);
      expect(p.hasMore, isTrue);

      final more = p.loadMore(); // page 2 in flight …
      final again = p.refresh(); // … the list is replaced meanwhile (what a new search does)
      await Future.wait([more, again]);
      expect(p.loadingMore, isFalse);
      expect(p.items.length, 20);

      await p.loadMore();
      expect(p.items.length, 40);
      p.dispose();
      });
    });

    testWidgets('a failed refresh keeps the rows and reports the error', (tester) async {
      await tester.runAsync(() async {
      var fail = false;
      final api = FakeApi({
        ...peopleRoutes(),
        'GET /api/v1/admin/users': (o) => fail ? const FakeResponse(500, {'detail': 'Database is busy'}) : usersList(o),
      }, latency: const Duration(milliseconds: 50));
      await peopleSetUp(api);
      final p = AdminAdminsProvider();
      await p.refresh();
      expect(p.items, isNotEmpty);
      fail = true;
      await p.refresh();
      expect(p.items, isNotEmpty);
      expect(p.failed, isTrue);
      expect(p.errorMessage, isNotNull);
      fail = false;
      await p.refresh();
      expect(p.failed, isFalse);
      expect(p.errorMessage, isNull);
      p.dispose();
      });
    });

    testWidgets('the page shows the rows as a table with the Add admin action', (tester) async {
      await bigView(tester);
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminAdminsPage(embedded: true), scale: 1)));
      await pumpFrames(tester);
      expect(find.byWidgetPredicate((w) => w is AppDataTable), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('admin_add_admin'.tr), findsOneWidget);
      await close(tester);
    });
  });

  group('View as', () {
    testWidgets('role tabs, a search field without the stray arrow button, rows from the server', (tester) async {
      await bigView(tester);
      final api = FakeApi(peopleRoutes(), latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminViewAsPage(), scale: 1)));
      await pumpFrames(tester);
      expect(find.byType(AppTabs), findsOneWidget);
      expect(find.byType(AppSearchField), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(find.text('سارة أحمد 1'), findsOneWidget);
      // switching to teachers asks the server for role=teacher
      api.reset();
      await tester.tap(find.text('teacher'.tr));
      await pumpFrames(tester);
      expect(api.calls.map((c) => c.query['role']), contains('teacher'));
      await close(tester);
    });

    testWidgets('a failed load shows the server message with Retry, not a raw exception', (tester) async {
      await bigView(tester);
      final api = FakeApi({
        ...peopleRoutes(),
        'GET /api/v1/admin/users': (_) => const FakeResponse(500, {'detail': 'Database is busy'}),
      }, latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(auth, layoutHost(const AdminViewAsPage(), scale: 1)));
      await pumpFrames(tester);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.text('retry'.tr), findsWidgets);
      await close(tester);
    });
  });

  group('My account', () {
    testWidgets('leaving the page while it loads or saves does not touch the disposed controllers', (tester) async {
      await bigView(tester, const Size(900, 1400));
      final api = FakeApi({
        ...peopleRoutes(),
        'GET /api/v1/admin/me': (_) => {'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'super-admin'},
      }, latency: const Duration(milliseconds: 300));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(
        auth,
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(storage: peopleStorage),
          child: layoutHost(const AdminProfilePage(), scale: 1),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // gone before the answer arrives
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save is the primary action and stays disabled until something changes', (tester) async {
      await bigView(tester, const Size(900, 1400));
      final api = FakeApi({
        ...peopleRoutes(),
        'GET /api/v1/admin/me': (_) => {'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'super-admin'},
      }, latency: const Duration(milliseconds: 50));
      final auth = await peopleSetUp(api);
      await tester.pumpWidget(peopleProviders(
        auth,
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(storage: peopleStorage),
          child: layoutHost(const AdminProfilePage(), scale: 1),
        ),
      ));
      await pumpFrames(tester);
      final save = tester.widget<AppButton>(find.byKey(const ValueKey('profile_save')));
      expect(save.variant, AppButtonVariant.primary);
      expect(save.onPressed, isNull);
      await tester.enterText(find.byType(TextFormField).first, 'Boss Two');
      await pumpFrames(tester, 3);
      expect(tester.widget<AppButton>(find.byKey(const ValueKey('profile_save'))).onPressed, isNotNull);
      await close(tester);
    });
  });
}
