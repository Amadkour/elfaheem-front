// VISUAL review renders of the sheets made to size to their content (D-710) with a toned header (D-711): the Google
// Forms import of the owner's screenshot (empty and with a form picked), a short list picker and a delete sheet,
// opened over a page at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/sheets_d710_<scene>_*.png. The `forms_before_*` images were rendered once from c8fc07d3 (the
// full-height side panel) for comparison; they are not regenerated. Not a CI suite; compared by eye.
//
//   flutter test test/visual/sheets_d710_golden_test.dart --update-goldens [--plain-name forms]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/exams/exam_forms_import.dart';
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

/// The page under every scene: a header and a few cards.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(AppSpace.lg), children: [
        Text(_tr('الأسئلة', 'Questions'), style: AppType.headline(context)),
        AppSpace.gapMd,
        for (final (ar, en) in const [('يدوي', 'Manual'), ('ارفع ملف امتحان جاهز', 'Upload a ready exam'), ('استيراد من Google Forms', 'Import from Google Forms')])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppCard(child: Text(_tr(ar, en), style: AppType.bodyStrong(context))),
          ),
      ]);
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

Widget _formsBody({FormPreview? preview}) => GoogleFormsImportBody(
      loading: false,
      connected: true,
      waiting: false,
      preview: preview,
      sections: const [],
      sectionId: null,
      onSection: (_) {},
      report: null,
      busy: false,
      error: null,
      onConnect: () {},
      onPick: () {},
      onImport: () {},
      onDone: () {},
      creating: true,
    );

final _preview = FormPreview(
  title: 'Physics — Unit 3 quiz',
  isQuiz: true,
  rows: [for (var i = 0; i < 12; i++) {'needs_answer': i > 9}],
  skipped: const [('Upload your work', 'file_upload')],
);

/// The sheets, opened over the page from the Navigator's own context.
final _scenes = <String, void Function(BuildContext)>{
  'forms': (c) => showAppSheet<void>(
        c,
        (_) => AppSheetContent(
            tone: AppTone.info,
            icon: Icons.dynamic_form_outlined,
            title: _tr('استيراد من Google Forms', 'Import from Google Forms'),
            children: [_formsBody()]),
      ),
  'forms_picked': (c) => showAppSheet<void>(
        c,
        (_) => AppSheetContent(
            tone: AppTone.info,
            icon: Icons.dynamic_form_outlined,
            title: _tr('استيراد من Google Forms', 'Import from Google Forms'),
            children: [_formsBody(preview: _preview)]),
      ),
  'list': (c) => showAppSheet<void>(
        c,
        (ctx) => AppSheetContent(
          icon: Icons.menu_book_rounded,
          title: _tr('لأي مقرر هذا الاختبار؟', 'Which course is this exam for?'),
          children: [
            for (final (ar, en, n) in const [('الفيزياء ١', 'Physics 1', 42), ('الرياضيات', 'Mathematics', 38), ('الكيمياء', 'Chemistry', 27), ('الأحياء', 'Biology', 31)])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.class_outlined),
                title: Text(_tr(ar, en)),
                subtitle: Text(countText(n, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {},
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(_tr('بلا مقرر (اختبار شخصي)', 'No course (a personal exam)')),
              onTap: () {},
            ),
          ],
        ),
      ),
  'delete': (c) => showAppSheet<void>(
        c,
        (ctx) => AppSheetContent(
          tone: AppTone.danger,
          icon: Icons.delete_outline_rounded,
          title: _tr('حذف «اختبار الوحدة الثالثة»؟', 'Delete “Unit 3 quiz”?'),
          children: [
            Text(
                _tr('تُحذف الأسئلة و٢٤ محاولة مع درجاتها. لا يمكن التراجع عن الحذف.',
                    'Its questions and 24 attempts with their marks are deleted. This cannot be undone.'),
                style: AppType.body(ctx)),
            AppSpace.gapLg,
            Row(children: [
              Expanded(child: AppButton.ghost(label: _tr('إلغاء', 'Cancel'), onPressed: () {})),
              AppSpace.gapSm,
              Expanded(child: AppButton.danger(label: _tr('حذف', 'Delete'), onPressed: () {})),
            ]),
          ],
        ),
      ),
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
                matchesGoldenFile('goldens/sheets_d710_${scene.key}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
              );
            }
          }
        }
      } finally {
        AppConfig.lang = prevLang;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        debugDisableShadows = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
