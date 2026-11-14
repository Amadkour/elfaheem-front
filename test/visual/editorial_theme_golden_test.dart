// VISUAL review renders (not a CI suite): the Warm Editorial default (D-610 – D-613) on the built-in palette — the
// editorial type roles, the five block tones, and raw Material widgets (buttons, inputs, chips, tabs, a dialog body,
// a navigation bar) styled only by ThemeData — at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/editorial_theme_*.png. Compared by eye.
//
//   flutter test test/visual/editorial_theme_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
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
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class _Sample extends StatelessWidget {
  const _Sample();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width > 900;
    Widget blockBody(String title, String body, IconData icon, {String? figure, Color? figureColor}) => Builder(
          builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: AppIconSize.lg),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.section(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(body, style: AppType.body(context).copyWith(color: b.muted)),
                ]),
              ),
              if (figure != null)
                Text(figure, style: AppType.figureLarge(context).copyWith(color: b.accentInk(figureColor ?? b.ink))),
            ]);
          },
        );
    final blocks = <Widget>[
      AppBlock(
        tone: AppBlockTone.peach,
        hero: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tr('درس اليوم', "Today's lesson"), style: AppType.meta(context).copyWith(color: AppBlock.colorsOf(context).faint)),
          const SizedBox(height: AppSpace.xs),
          Text(_tr('الكسور العشرية وتقريبها', 'Decimals and rounding'), style: AppType.display(context)),
          const SizedBox(height: AppSpace.xs),
          Text(_tr('اقرأ الفقرة ثم أجب عن خمسة أسئلة قبل البث المباشر.', 'Read the passage, then answer five questions before the live session.'),
              style: AppType.body(context)),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.play_arrow_rounded), label: Text(_tr('ابدأ الدرس', 'Start the lesson'))),
        ]),
      ),
      AppBlock(
          tone: AppBlockTone.sky,
          child: blockBody(_tr('الجلسة القادمة', 'Next session'), _tr('الخميس ٤:٣٠ م · مع د. منى عادل', 'Thursday 4:30 PM · with Dr. Mona Adel'),
              Icons.event_rounded)),
      AppBlock(
          tone: AppBlockTone.gold,
          child: blockBody(_tr('سلسلة الأيام', 'Your streak'), _tr('سبعة أيام متتالية من التعلم', 'Seven days of learning in a row'),
              Icons.local_fire_department_rounded,
              figure: '7', figureColor: c.accent2)),
      AppBlock(
          tone: AppBlockTone.emerald,
          child: blockBody(_tr('اكتمل', 'Completed'), _tr('أنهيت وحدة الدوال', 'You finished the functions unit'), Icons.check_circle_rounded,
              figure: '92%', figureColor: c.success)),
      AppBlock(
          tone: AppBlockTone.paper,
          child: blockBody(_tr('ملاحظة', 'A note'), _tr('كتلة بلا لون: سطح البطاقة وخط دافئ', 'A block without colour: the card surface and a warm hairline'),
              Icons.sticky_note_2_rounded)),
    ];
    final material = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tr('عناصر Material من الثيم', 'Material widgets from the theme'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            FilledButton(onPressed: () {}, child: Text(_tr('حفظ', 'Save'))),
            OutlinedButton(onPressed: () {}, child: Text(_tr('معاينة', 'Preview'))),
            TextButton(onPressed: () {}, child: Text(_tr('إلغاء', 'Cancel'))),
            FilledButton.tonal(onPressed: () {}, child: Text(_tr('تصدير', 'Export'))),
            const FilledButton(onPressed: null, child: Text('—')),
          ]),
          const SizedBox(height: AppSpace.md),
          TextField(decoration: InputDecoration(labelText: _tr('البريد الإلكتروني', 'Email'), hintText: 'name@example.test')),
          const SizedBox(height: AppSpace.sm),
          TextField(
              autofocus: true,
              decoration: InputDecoration(labelText: _tr('الاسم (مُركَّز)', 'Name (focused)'), prefixIcon: const Icon(Icons.person_rounded))),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            ChoiceChip(label: Text(_tr('الكل', 'All')), selected: true, onSelected: (_) {}),
            ChoiceChip(label: Text(_tr('نشط', 'Active')), selected: false, onSelected: (_) {}),
            FilterChip(label: Text(_tr('معلّق', 'Pending')), selected: true, onSelected: (_) {}),
          ]),
          const SizedBox(height: AppSpace.md),
          const LinearProgressIndicator(value: 0.64),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Checkbox(value: true, onChanged: (_) {}),
            Radio<int>(value: 1, groupValue: 1, onChanged: (_) {}),
            const Spacer(),
            const Badge(label: Text('3'), child: Icon(Icons.notifications_rounded)),
          ]),
          const Divider(height: AppSpace.lg),
          ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(_tr('ملفات الدورة', 'Course files')),
              subtitle: Text(_tr('١٢ ملفاً', '12 files')),
              trailing: const Icon(Icons.chevron_right_rounded)),
          const SizedBox(height: AppSpace.md),
          // a dialog's body, drawn in place (AlertDialog without the route)
          AlertDialog(
            title: Text(_tr('حذف المادة؟', 'Delete the material?')),
            content: Text(_tr('لا يمكن التراجع عن هذا.', 'This cannot be undone.')),
            actions: [
              TextButton(onPressed: () {}, child: Text(_tr('إلغاء', 'Cancel'))),
              FilledButton(onPressed: () {}, child: Text(_tr('حذف', 'Delete'))),
            ],
          ),
        ]),
      ),
    );
    final nav = NavigationBar(selectedIndex: 0, destinations: [
      NavigationDestination(icon: const Icon(Icons.home_rounded), label: _tr('الرئيسية', 'Home')),
      NavigationDestination(icon: const Icon(Icons.menu_book_rounded), label: _tr('كورساتي', 'Courses')),
      NavigationDestination(icon: const Icon(Icons.event_rounded), label: _tr('الجدول', 'Schedule')),
    ]);
    final type = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_tr('صباح الخير يا سارة', 'Good morning, Sara'), style: AppType.display(context)),
      Text(_tr('عنوان رئيسي للبطل', 'A hero headline'), style: AppType.headline(context)),
      Text(_tr('عنوان الصفحة', 'Page title'), style: AppType.pageTitle(context)),
      Text(_tr('عنوان القسم', 'Section heading'), style: AppType.section(context)),
      Text(_tr('نص الفقرة بخط الواجهة الذي اختاره الشخص.', 'Body text in the UI sans the person chose.'), style: AppType.body(context)),
    ]);
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      type,
      const SizedBox(height: AppSpace.lg),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: [for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: b)])),
          AppSpace.gapLg,
          Expanded(child: material),
        ])
      else ...[
        for (final b in blocks) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: b),
        material,
      ],
      const SizedBox(height: AppSpace.md),
      nav,
    ]);
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('editorial theme sample', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(size.width, size.width > 900 ? 1500 : 2700);
            final theme = ThemeConfigProvider(api: ApiClient());
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(ThemeConfigScope(
              provider: theme,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme(dark: false),
                darkTheme: theme.materialTheme(dark: true),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, w) => Directionality(
                    textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                    child: DefaultTextStyle.merge(style: TextStyle(fontFamilyFallback: AppFonts.fallback), child: w!)),
                home: RepaintBoundary(
                  key: _shot,
                  child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: const _Sample())),
                ),
              ),
            ));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/editorial_theme_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
