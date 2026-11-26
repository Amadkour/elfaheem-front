// Review renders of the shell for student, teacher, parent, admin and super admin (KIT_SPEC §7.3): five demo tabs,
// the second tab open, one count; plus the kit gallery page itself. The shell paint itself is rd/kit-shell's (steps
// 12-13); this file renders whatever shell the branch has. Not a CI suite.
//
//   flutter test test/visual/redesign/kit_shell_golden_test.dart --update-goldens [--plain-name teacher]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/gallery/kit_gallery_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

List<DashboardItem> _items() => [
      DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', null,
          Center(child: Text(_t('الرئيسية', 'Home')))),
      DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, 'my_courses', null,
          Builder(builder: (context) => _tabBody(context)), badge: 3),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'schedule', null, const SizedBox()),
      DashboardItem(Icons.extension_outlined, Icons.extension_rounded, 'games', null, const SizedBox()),
      DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, 'my_profile', null, const SizedBox()),
    ];

Widget _tabBody(BuildContext context) => ListView(
      padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
      children: [
        AppHero(
          title: _t('دوراتي', 'My courses'),
          subtitle: _t('٤ دورات، تقدّمك ٦٢٪', '4 courses, 62% progress'),
          overlap: false,
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          title: _t('كمّل من وين وقفت', 'Pick up where you left off'),
          child: AppTile(
            icon: Icons.functions_rounded,
            title: _t('الرياضيات', 'Maths'),
            subtitle: _t('الدوال الأسية', 'Exponential functions'),
            trailing: const AppProgressRing(value: .38),
            onTap: () {},
          ),
        ),
      ],
    );

Widget _shell(AppRoleAccent? role) => LayoutBuilder(builder: (context, box) {
      final shell = AppShell(width: box.maxWidth, currentIndex: 1, onTap: (_) {}, items: _items(), unreadCount: 1);
      return role == null ? shell : AppAreaScope.role(role: role, budget: false, child: shell);
    });

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  for (final (name, role) in [
    ('student', null),
    ('teacher', AppRoleAccent.teacher),
    ('parent', AppRoleAccent.parent),
    ('admin', AppRoleAccent.admin),
    ('super', AppRoleAccent.superAdmin),
  ]) {
    testWidgets(name, (t) => kitRender(t, 'kit_shell_$name', () => _shell(role),
        storage: storage, grow: false, scaffold: false, modes: const [false]));
  }

  testWidgets('gallery page', (t) => kitRender(t, 'kit_gallery', () => const KitGalleryPage(),
      storage: storage, scaffold: false, grow: false, modes: const [false]));
}
