// VISUAL review renders (not a CI suite): the quieter light-mode washes of D-728 — the new-exam wizard's Copies step
// with a selected card, a sheet with its header band and two note rows, and a list of selectable rows / chips — at
// 390x844 and 1440x900, ar, light (and dark once, to check it did not move), into
// test/visual/goldens/ux_tint_<TINT_TAG>_*.png. Set TINT_TAG=before on the old code to compare by eye.
//
//   TINT_TAG=after flutter test test/visual/ux_tint_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/design/app_sheet_header.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_wizard.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart' show SetupChoiceTile;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
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
final _tag = Platform.environment['TINT_TAG'] ?? 'after';

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: child,
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(const {}, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final dark in const [false, true]) {
        if (dark && size.width > 400) continue; // one dark render: dark mode is not meant to move
        AppConfig.lang = 'ar';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(build(), dark: dark));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final e = tester.takeException();
        expect(e, isNull, reason: '$name ${size.width.toInt()}: $e');
        await expectLater(find.byKey(_shot),
            matchesGoldenFile('goldens/ux_tint_${_tag}_${name}_${size.width.toInt()}_${dark ? 'dark' : 'light'}.png'));
      }
    }
  } finally {
    fake.uninstall();
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

QuickQuestion _mcq(String prompt) {
  final q = QuickQuestion.ofType('mcq_single')
    ..prompt = prompt
    ..correct = 'a';
  for (var i = 0; i < q.options.length; i++) {
    q.options[i].text = ['2', '3', '4', '5'][i];
  }
  return q;
}

/// A course exam on paper, a ready bubble form, one generic copy chosen (the owner's screenshot).
ExamCreatePlan _copiesPlan() {
  final p = ExamCreatePlan(place: (courseId: null, orgId: null, name: 'بدون مقرر (اختبار شخصي)'), title: 'اختبار قصير')..setOffline(true);
  for (var i = 0; i < 17; i++) {
    p.exam.questions.add(_mcq('Q$i'));
  }
  p
    ..setLayout(PaperLayout.bubbleObjective)
    ..template = const OmrTemplateItem(id: 3, version: 1, name: 'Mine', questions: 150, kind: 'auto_bubble')
    ..bubbleForm = BubbleFormSource.imported
    ..setCopies(SheetCopies.generic);
  return p;
}

/// A sheet as the bubble print sheet draws it: the header band, two note rows (one with a Change action), a line.
Widget _sheet() => Builder(builder: (context) {
      final c = context.colors;
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: Material(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const AppSheetHeader('طباعة أوراق التظليل'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AppBanner(
                        icon: Icons.tune_rounded,
                        text: 'اخترت مسبقًا ما يحدث لأسئلة لا تتسع لها الورقة.',
                        action: TextButton(onPressed: () {}, child: const Text('غيّر')),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      const AppBanner(icon: Icons.info_outline_rounded, text: 'قالب مخصص: اطبع ورقتك الأصلية — يطبع النظام الأوراق المدمجة فقط'),
                      const SizedBox(height: AppSpace.sm),
                      Text('15 سؤالًا على ورقة من 150 سؤالًا · رقم الطالب بالتظليل', style: AppType.body(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    });

/// Selectable rows: two choice tiles (one selected), a selected list tile and selected filter chips.
Widget _rows() => Builder(builder: (context) {
      final c = context.colors;
      return Scaffold(
        backgroundColor: c.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SetupChoiceTile(icon: Icons.badge_outlined, title: 'نسخة لكل طالب', subtitle: 'باسم كل طالب وبياناته', selected: false, onTap: () {}),
                const SizedBox(height: AppSpace.sm),
                SetupChoiceTile(icon: Icons.copy_all_rounded, title: 'نسخة عامة واحدة', subtitle: 'تُطبع بعدد الحاضرين، ويكتب الطالب اسمه ورقمه', selected: true, onTap: () {}),
                const SizedBox(height: AppSpace.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (i, n) in ['الفصل الأول', 'الفصل الثاني', 'الفصل الثالث'].indexed)
                      ListTile(
                        title: Text(n),
                        selected: i == 1,
                        // the selected-row fill the org pages use (gov_ui, gov_route_sheet)
                        tileColor: i == 1 ? _tag == 'before' ? c.primary.withValues(alpha: 0.07) : Color.alphaBlend(c.primary.withValues(alpha: 0.05), c.cardBg) : null,
                        trailing: i == 1 ? Icon(Icons.check_rounded, color: c.primary) : null,
                      ),
                  ]),
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(spacing: AppSpace.xs, children: [
                  for (final (i, n) in ['الكل', 'مفتوح', 'مغلق'].indexed)
                    ChoiceChip(
                      label: Text(n, style: AppType.meta(context).copyWith(color: i == 0 ? c.primary : c.textMedium, fontWeight: FontWeight.w600)),
                      selected: i == 0,
                      showCheckmark: false,
                      selectedColor: _tag == 'before' ? c.primary.withValues(alpha: 0.14) : Color.alphaBlend(c.primary.withValues(alpha: 0.05), c.cardBg),
                      backgroundColor: c.inputBg,
                      side: BorderSide(color: i == 0 ? c.primary : c.divider),
                      onSelected: (_) {},
                    ),
                ]),
              ]),
            ),
          ),
        ),
      );
    });

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('copies', (t0) => _render(t0, 'copies', () => ExamCreateWizard(initialPlan: _copiesPlan(), initialStep: CreateStep.sheets)));
  testWidgets('sheet', (t0) => _render(t0, 'sheet', _sheet));
  testWidgets('rows', (t0) => _render(t0, 'rows', _rows));
}
