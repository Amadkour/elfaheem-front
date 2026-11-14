// VISUAL review renders of the shared overlays and list kit after the editorial restyle (D-612): the data table with
// its pagination (paper cards on the phone, one paper surface on the desktop), then each overlay opened over that
// page — the dialog, the confirm, a sheet with AppSheetContent, the share sheet, the drawer and the notice — at
// 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/kit_overlays_<scene>_*.png. Not a CI suite;
// compared by eye.
//
//   flutter test test/visual/kit_overlays_golden_test.dart --update-goldens [--plain-name dialog]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';

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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

typedef _Row = (String name, String email, String status, int courses, double paid);

final _rows = <_Row>[
  ('سارة أحمد', 'sara@example.test', 'active', 3, 1250),
  ('Omar Khaled', 'omar@example.test', 'pending', 1, 0),
  ('ليلى محمود', 'laila@example.test', 'active', 5, 4380.5),
  ('Youssef Ali', 'youssef@example.test', 'inactive', 0, 0),
  ('منى إبراهيم', 'mona@example.test', 'active', 2, 900),
  ('Karim Nabil', 'karim@example.test', 'active', 4, 2100),
];

/// The page under every scene: a page header and the table with its pagination.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    AppTone tone(String s) => switch (s) { 'active' => AppTone.success, 'pending' => AppTone.warning, _ => AppTone.neutral };
    String label(String s) => switch (s) {
          'active' => _tr('نشط', 'Active'),
          'pending' => _tr('بانتظار', 'Pending'),
          _ => _tr('غير نشط', 'Inactive'),
        };
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(children: [
      AppPageHeader(
        title: _tr('الطلاب', 'Students'),
        subtitle: _tr('كل المسجّلين هذا الفصل', 'Everyone enrolled this term'),
        icon: Icons.school_rounded,
        onRefresh: () {},
        updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        primaryAction: AppButton.primary(label: _tr('دعوة', 'Invite'), icon: Icons.add_rounded, onPressed: () {}),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(g, AppSpace.lg, g, AppSpace.xl),
        child: AppDataTable<_Row>(
          shrinkWrap: true,
          rows: _rows,
          searchHint: _tr('ابحث بالاسم أو البريد', 'Search by name or email'),
          onSearch: (_) {},
          sortKey: 'paid',
          sortAscending: false,
          onSort: (_, _) {},
          onRowTap: (_) {},
          rowId: (r) => r.$2,
          selectedRowId: 'laila@example.test',
          filters: [
            AppTableFilter(
              label: _tr('الحالة', 'Status'),
              options: [('active', label('active')), ('pending', label('pending')), ('inactive', label('inactive'))],
              value: 'active',
              onChanged: (_) {},
            ),
          ],
          columns: [
            AppTableColumn.text(key: 'name', label: _tr('الاسم', 'Name'), text: (r) => r.$1, primary: true, sortable: true, flex: 2),
            AppTableColumn.text(key: 'email', label: _tr('البريد', 'Email'), text: (r) => r.$2, flex: 2, showOnPhone: false),
            AppTableColumn(
                key: 'status',
                label: _tr('الحالة', 'Status'),
                cell: (_, r) => Align(alignment: AlignmentDirectional.centerStart, child: AppStatusBadge(label: label(r.$3), tone: tone(r.$3)))),
            AppTableColumn.text(key: 'courses', label: _tr('الكورسات', 'Courses'), text: (r) => '${r.$4}', numeric: true),
            AppTableColumn.text(key: 'paid', label: _tr('المدفوع', 'Paid'), text: (r) => r.$5.toStringAsFixed(0), numeric: true, sortable: true),
          ],
          rowActions: (r) => [
            AppRowAction(icon: Icons.visibility_rounded, label: _tr('عرض', 'View'), onTap: () {}),
            AppRowAction(icon: Icons.delete_outline_rounded, label: _tr('حذف', 'Delete'), onTap: () {}, danger: true),
          ],
          pagination: AppPagination(page: 2, pageCount: 9, onPage: (_) {}, total: 52, pageSize: 6, onPageSize: (_) {}),
        ),
      ),
    ]);
  }
}

Widget _host({required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: const _Page())),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The overlays, opened over the page from the Navigator's own context.
final _scenes = <String, void Function(BuildContext)>{
  'table': (_) {},
  'dialog': (c) => showAppDialog<void>(
        c,
        title: _tr('إنهاء الفصل الدراسي؟', 'Close the term?'),
        icon: Icons.event_busy_rounded,
        danger: true,
        body: Text(_tr(
            'تُقفل الدرجات وتُرسل التقارير إلى أولياء الأمور. لا يمكن التراجع عن هذه الخطوة بعد الإرسال.',
            'Grades lock and the reports go out to parents. There is no way back once they are sent.')),
        actions: [
          AppButton.ghost(label: _tr('إلغاء', 'Cancel'), onPressed: () {}),
          AppButton.danger(label: _tr('إنهاء الفصل', 'Close the term'), onPressed: () {}),
        ],
      ),
  'confirm': (c) => appConfirm(c,
      message: _tr('حذف الطالبة ليلى محمود من هذا الكورس؟', 'Remove Laila Mahmoud from this course?'),
      danger: true,
      confirmLabel: _tr('حذف', 'Remove')),
  'sheet': (c) => showAppSheet<void>(
        c,
        (_) => AppSheetContent(
          title: _tr('تصفية الطلاب', 'Filter students'),
          children: [
            Text(_tr('الحالة', 'Status'), style: AppType.label(c)),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppChoiceChip(label: _tr('الكل', 'All'), selected: true, onTap: () {}),
              AppChoiceChip(label: _tr('نشط', 'Active'), selected: false, onTap: () {}),
              AppChoiceChip(label: _tr('بانتظار', 'Pending'), selected: false, onTap: () {}),
            ]),
            AppSpace.gapLg,
            Text(_tr('الكورس', 'Course'), style: AppType.label(c)),
            AppSpace.gapXs,
            for (final name in [_tr('الفيزياء ١', 'Physics 1'), _tr('الرياضيات', 'Mathematics'), _tr('الكيمياء', 'Chemistry')])
              AppSwitchTile(title: name, value: name.contains('F') || name.contains('ف'), onChanged: (_) {}),
            AppSpace.gapLg,
            AppButton.primary(label: _tr('تطبيق', 'Apply'), expand: true, onPressed: () {}),
          ],
        ),
      ),
  'share': (c) => showAppShareSheet(c,
      url: 'https://alfheemacademy.com/s/meeting/12',
      title: _tr('اجتماع أولياء الأمور', 'Parents meeting'),
      subtitle: _tr('الخميس ٤ م', 'Thursday, 4 pm'),
      kind: _tr('اجتماع', 'Meeting'),
      icon: Icons.groups_rounded,
      hint: _tr('يمكن لأي شخص لديه الرابط الانضمام', 'Anyone with the link can join')),
  'drawer': (c) => showAppDrawer<void>(
        c,
        title: _tr('تعديل الطالبة', 'Edit student'),
        builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppField(label: _tr('الاسم', 'Name'), controller: TextEditingController(text: 'ليلى محمود')),
          AppSpace.gapMd,
          AppField(label: _tr('البريد', 'Email'), controller: TextEditingController(text: 'laila@example.test')),
          AppSpace.gapMd,
          AppSwitchTile(title: _tr('نشط', 'Active'), value: true, onChanged: (_) {}),
        ]),
        actions: [
          AppButton.ghost(label: _tr('إلغاء', 'Cancel'), onPressed: () {}),
          AppButton.primary(label: _tr('حفظ', 'Save'), onPressed: () {}),
        ],
      ),
  'notice': (_) => showAppNotice(_tr('تم حفظ التغييرات', 'Changes saved'), actionLabel: _tr('تراجع', 'Undo'), onAction: () {}),
  'notice_error': (_) => showAppNotice(_tr('تعذّر الحفظ، حاول مرة أخرى', 'Could not save, try again'), error: true),
};

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  for (final scene in _scenes.entries) {
    testWidgets(scene.key, (tester) async {
      final prevLang = AppConfig.lang;
      debugDisableShadows = false;
      try {
        for (final size in const [Size(390, 844), Size(1440, 900)]) {
          for (final lang in const ['ar', 'en']) {
            for (final dark in const [false, true]) {
              AppConfig.lang = lang;
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              await tester.pumpWidget(const SizedBox());
              await tester.pumpWidget(_host(dark: dark));
              await _frames(tester, 4);
              scene.value(navigatorKey.currentContext!);
              await _frames(tester);
              final e = tester.takeException();
              expect(e, isNull, reason: '${scene.key} ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
              await expectLater(
                find.byKey(_shot),
                matchesGoldenFile('goldens/kit_overlays_${scene.key}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
              );
              hideAppNotice();
              await _frames(tester, 3);
            }
          }
        }
      } finally {
        AppConfig.lang = prevLang;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 7));
        debugDisableShadows = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
