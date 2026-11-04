// VISUAL review renders of the Super Admin shell pieces (Overview, a hub tab, the global search palette) at 390x844 and
// 1440x900 in Arabic and English, light, into test/visual/goldens/shell_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/shell_dashboard_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_global_search.dart';
import 'package:flutter_education_app/features/admin/admin_home_body.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminPendingPayoutsProvider;
import 'package:flutter_education_app/features/admin/admin_services_hub.dart';
import 'package:flutter_education_app/features/admin/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/admin_home_layout_test.dart' as base;
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, StorageService storage) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
      ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
      ChangeNotifierProvider(create: (_) => AdminPendingPayoutsProvider()),
      ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
      ChangeNotifierProvider(create: (_) => ComplaintProvider()),
    ],
    child: ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: RepaintBoundary(
          key: _shot,
          child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
        ),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

void main() {
  late StorageService storage;

  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
  });

  Future<void> shoot(WidgetTester tester, String name, Widget Function() build, {bool grow = true}) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), storage));
          await _frames(tester);
          for (var i = 0; i < 4 && grow; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/shell_${name}_${size.width.toInt()}_$lang.png'));
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  testWidgets('overview', (tester) async {
    await shoot(
      tester,
      'overview',
      () => AdminHomeBody(
        data: AdminHomeData.fromOverview(base.fullPayload()),
        name: _tr('أحمد حمدي', 'Ahmed Hamdy'),
        pendingPayouts: 5,
        actions: AdminHomeActions(openAlert: (_) {}, openStudents: () {}, openIncome: () {}),
      ),
    );
  });

  testWidgets('hub finance', (tester) async {
    await shoot(tester, 'hub', () => const AdminServicesHub(groupId: 'finance'));
  });

  testWidgets('hub config', (tester) async {
    await shoot(tester, 'hub_config', () => const AdminServicesHub(groupId: 'config'));
  });

  testWidgets('global search', (tester) async {
    Future<List<AdminSearchGroup>> search(String q) async => parseAdminSearch({
          'groups': [
            {
              'kind': 'students',
              'total': 14,
              'items': [
                {'id': 7, 'label': 'سارة أحمد', 'sub': 'sara@example.test', 'username': 'sara', 'status': 'active'},
                {'id': 9, 'label': 'Sami Hassan', 'sub': 'sami@example.test', 'username': null, 'status': 'inactive'},
              ],
            },
            {
              'kind': 'courses',
              'total': 1,
              'items': [
                {'id': 3, 'label': 'الفيزياء الحديثة', 'sub': 'Dr. Omar', 'username': null, 'status': 'published'},
              ],
            },
          ],
        });
    await shoot(
      tester,
      'search',
      () {
        final c = AdminSearchController(
          pages: [
            AdminSearchPage(label: _tr('المدفوعات', 'Payments'), desc: _tr('كل المدفوعات', 'Every payment'), group: _tr('المالية', 'Finance'), icon: Icons.receipt_long_rounded, onOpen: () {}),
            AdminSearchPage(label: _tr('طلبات السحب', 'Payout requests'), group: _tr('المالية', 'Finance'), icon: Icons.account_balance_wallet_rounded, onOpen: () {}),
          ],
          debounce: Duration.zero,
          search: search,
        )..setQuery(_tr('مد', 'pay'));
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
            child: AdminSearchPanel(controller: c, wide: true, onSelect: (_) {}),
          ),
        );
      },
      grow: false,
    );
  });
}
