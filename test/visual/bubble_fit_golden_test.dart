// Visual review renders of the bubble-fit panel (D-720 – D-722), inside the real "Print bubble sheets" sheet
// (showAppSheet: a side panel on desktop, a bottom sheet on a phone). NOT a CI suite:
//
//   flutter test test/visual/bubble_fit_golden_test.dart --update-goldens [--plain-name start]
//
// → test/visual/goldens/bubble_fit_<scene>_<width>_<lang>_<light|dark>.png at 390×844, 1440×900 and 391×2000 (the whole panel):
//   start    three questions that do not fit, nothing chosen yet, a 5-choice sheet offered, one question trimmed earlier
//   chosen   a trim with its preview (the struck choice, the correct one ticked), Leave off the sheet, Apply enabled
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
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/bubble_fit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/bubble_fit_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Map<String, dynamic> _opt(String id, String text, {bool correct = false}) => {'id': id, 'text': text, 'correct': correct};

BubbleFit _fit() => BubbleFit.fromJson({
      'template_id': 3,
      'sheet_options': 4,
      'written_sheet': 'NB2',
      'locked': false,
      'org_id': 1,
      'items': [
        {
          'question_id': 31, 'n': 3, 'type': 'mcq_single', 'count': 5, 'can_trim': true, 'trim_removes': ['e'],
          'prompt': '________ is define as using of the internet to network and empower business processes',
          'options': [_opt('a', 'E-Commerce'), _opt('b', 'E-Business', correct: true), _opt('c', 'Both a and b'), _opt('d', 'None of above'), _opt('e', 'All of the above')],
        },
        {
          'question_id': 37, 'n': 9, 'type': 'mcq_single', 'count': 5, 'can_trim': true, 'trim_removes': ['d'],
          'prompt': 'Which protocol secures web traffic?',
          'options': [_opt('a', 'HTTP'), _opt('b', 'FTP'), _opt('c', 'SMTP'), _opt('d', 'Telnet'), _opt('e', 'HTTPS', correct: true)],
        },
        {
          'question_id': 40, 'n': 12, 'type': 'mcq_multi', 'count': 5, 'can_trim': false, 'trim_removes': <String>[],
          'prompt': 'Select every cloud service model',
          'options': [for (final x in ['IaaS', 'PaaS', 'SaaS', 'FaaS', 'DaaS']) _opt(x.toLowerCase(), x, correct: true)],
        },
      ],
      'trimmed': [
        {'question_id': 33, 'n': 5, 'removed': ['e'], 'from_version': 1, 'to_version': 2},
      ],
    });

const _sheets = [OmrTemplateItem(id: 4, version: 1, name: 'Bubble sheet 100', questions: 100, options: 5)];

class _Panel extends StatefulWidget {
  const _Panel(this.initial);
  final Map<int, BubbleFitAction> initial;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  late final Map<int, BubbleFitAction> _chosen = {...widget.initial};
  final _fit0 = _fit();

  @override
  Widget build(BuildContext context) => AppSheetContent(title: t('طباعة أوراق التظليل', 'Print bubble sheets'), children: [
        BubbleFitView(
          fit: _fit0,
          chosen: _chosen,
          onChoose: (q, a) => setState(() => _chosen[q] = a),
          onAll: (a) {},
          onApply: () {},
          sheets: _sheets,
          onUseSheet: (_) {},
          onOwnSheet: () {},
          onRestore: (_) {},
        ),
      ]);
}

final _shot = GlobalKey();

Widget _host({required bool dark, required Map<int, BubbleFitAction> chosen}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => showAppSheet<void>(context, (_) => _Panel(chosen)));
        return Scaffold(body: Center(child: Text(t('تجهيز الاختبار وتسليمه', 'Prepare and deliver the exam'))));
      }),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Map<int, BubbleFitAction> chosen) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900), Size(391, 2000)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(dark: dark, chosen: chosen));
          for (var i = 0; i < 14; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/bubble_fit_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('start', (t) => _render(t, 'start', const {}));
  testWidgets('chosen', (t) => _render(t, 'chosen', const {31: BubbleFitAction.trim, 37: BubbleFitAction.written, 40: BubbleFitAction.ignore}));
}
