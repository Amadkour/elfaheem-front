// The organization dashboard's section pages on the shared page anatomy (D-103, org_page_kit.dart): Members,
// Departments, the joining inbox, Courses, Academic structure, Registrar, News, Forms, Complaints, Library and the
// Settings ("More") page, each at 320x640 and 1400x900, Arabic + English, textScaler 1.3, over a fake server whose
// payloads are shaped like the real one (org_pages_samples.dart) — with data and empty. Also the kit's behaviour:
// ONE primary action (a FAB on phones, a toolbar button when wide, never both), the filter / More menus, the part
// picker (tabs that fit, else one dropdown) and the section chips (one scrolling row).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/org/org_academic_pages.dart';
import 'package:flutter_education_app/features/org/org_courses_page.dart';
import 'package:flutter_education_app/features/org/org_dashboard_screen.dart';
import 'package:flutter_education_app/features/org/org_departments_page.dart';
import 'package:flutter_education_app/features/org/org_join_pages.dart';
import 'package:flutter_education_app/features/org/org_page_kit.dart';
import 'package:flutter_education_app/features/org/org_people_page.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/org/org_registrar_staff.dart';
import 'package:flutter_education_app/features/org/org_services_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';
import 'org_pages_samples.dart';

const _uni = {
  'id': 4,
  'name_ar': 'جامعة النيل الأهلية',
  'name_en': 'Nile National University',
  'type': 'university',
  'status': 'approved',
  'color': '#1F6F5C',
  'my_role': 'org_admin',
  'is_admin': true,
  'access': 'admin',
  'depth': 0,
  'permissions': <String, dynamic>{},
  'dept_permissions': <String, dynamic>{},
};

OrgSession _session() => OrgSession()
  ..loaded = true
  ..items = [_uni]
  ..currentId = 4;

Widget _page(Widget child) => ChangeNotifierProvider<OrgSession>.value(value: _session(), child: child);

Future<void> _show(WidgetTester tester, Widget w, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(layoutHost(w, scale: 1));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  FakeApi? fake;

  void install({bool empty = false}) {
    fake?.uninstall();
    fake = FakeApi({
      'GET /api/v1/org/mine': (_) => {'items': [_uni], 'can_create_root': false},
      'GET /api/v1/org/orgs/4/dashboard': (_) => payload('org_dashboard.json'),
      'GET /api/v1/notifications': (_) => {'items': [], 'total': 0, 'unread': 0},
      'GET /api/v1/me/attention': (_) => {'counts': {}, 'total': 0, 'items': []},
      ...orgPageRoutes(empty: empty),
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
      ..install();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    install();
  });

  tearDown(() {
    fake?.uninstall();
    fake = null;
  });

  final pages = <String, Widget Function()>{
    'members': () => const OrgPeoplePage(),
    'departments': () => const OrgDepartmentsPage(),
    'join inbox': () => const OrgJoinInboxPage(),
    'courses': () => const OrgCoursesPage(),
    'academic structure': () => const OrgAcademicPage(),
    'registrar': () => const OrgRegistrarPage(),
    'news': () => const OrgAnnouncementsPage(),
    'forms': () => const OrgFormsPage(),
    'complaints': () => const OrgComplaintsPage(),
    'library': () => const OrgMaterialsPage(),
  };

  for (final e in pages.entries) {
    testWidgets('${e.key}: no layout error with data and empty', (tester) async {
      await expectNoLayoutErrors(tester, () => _page(e.value()), frames: 6);
      install(empty: true);
      await expectNoLayoutErrors(tester, () => _page(e.value()), frames: 6);
    });
  }

  testWidgets('members: the filter and More menus open without a layout error', (tester) async {
    for (final key in const ['org.page.filter', 'org.page.more']) {
      await expectNoLayoutErrors(tester, () => _page(const OrgPeoplePage()), frames: 6, act: (t) async {
        await t.tap(find.byKey(ValueKey(key)).first);
      });
    }
  });

  testWidgets('members: ONE primary action — a FAB on a phone, a toolbar button when wide; More holds the file actions',
      (tester) async {
    AppConfig.lang = 'en';
    await _show(tester, _page(const OrgPeoplePage()), const Size(390, 844));
    expect(find.byKey(const ValueKey('org.page.add_member')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Add student'), findsOneWidget);
    // the kind is one segmented control, the status one filter showing the chosen value
    expect(find.byKey(const ValueKey('org.segment.1')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Import Excel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('org.page.more')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Import from Excel'), findsOneWidget);
    expect(find.text('Download the Excel template'), findsOneWidget);
    expect(find.text('Export (Excel · Word · PDF)'), findsOneWidget);

    await _show(tester, _page(const OrgPeoplePage()), const Size(1400, 900));
    expect(find.byKey(const ValueKey('org.page.add_member')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('More'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  testWidgets('part picker: quiet tabs when they fit, ONE dropdown when they do not', (tester) async {
    AppConfig.lang = 'en';
    var chosen = 0;
    Widget picker() => StatefulBuilder(
          builder: (context, set) => Padding(padding: const EdgeInsets.all(16), child: Column(children: [OrgPartPicker(
            parts: const [
              ('Decisions', Icons.gavel_rounded),
              ('Terms', Icons.date_range_rounded),
              ('Courses', Icons.menu_book_rounded),
              ('Programs', Icons.account_tree_rounded),
              ('Staff', Icons.badge_rounded),
              ('Rules', Icons.rule_rounded),
              ('Graduation & at risk', Icons.school_rounded),
            ],
            index: chosen,
            onChanged: (i) => set(() => chosen = i),
          )])),
        );
    await expectNoLayoutErrors(tester, picker);
    await _show(tester, picker(), const Size(1400, 900));
    expect(find.byKey(const ValueKey('org.part.picker')), findsNothing);
    expect(find.byKey(const ValueKey('org.part.6')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _show(tester, picker(), const Size(390, 844));
    expect(find.byKey(const ValueKey('org.part.picker')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('org.part.picker')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('org.part.option.5')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(chosen, 5);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
  });

  testWidgets('section chips: one row that scrolls (never wraps or overflows) at every size', (tester) async {
    Widget chips() => OrgSectionChips(
          items: const [
            ('Members', Icons.groups_rounded),
            ('Departments', Icons.apartment_rounded),
            ('Department join requests', Icons.how_to_reg_rounded),
          ],
          index: 2,
          onChanged: (_) {},
        );
    await expectNoLayoutErrors(tester, chips);
  });

  testWidgets('the real shell on People · Academics · Services · Settings: no layout error', (tester) async {
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Mona Adel', 'gmail': 'mona@example.com', 'role': 'org-admin'});
    for (final (section, sub) in const [('people', 'members'), ('academics', 'registrar'), ('services', 'complaints'), ('settings', null)]) {
      await expectNoLayoutErrors(tester, () {
        AttentionService.instance.orgTabRequest.value = OrgTabRequest(4, section, sub);
        return MultiProvider(providers: appProviders(storage: storage, api: ApiClient()), child: const OrgDashboardScreen());
      }, scaffold: false, frames: 12);
    }
  });
}
