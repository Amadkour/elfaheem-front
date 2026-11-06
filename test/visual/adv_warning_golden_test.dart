// Visual review renders of the Phase 6 early warning (D-289, docs/advising/PHASE6.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_warning_golden_test.dart --update-goldens [--plain-name rules]
//
// → test/visual/goldens/adv_warning_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   rules          a director's rules: the engine card, rules by kind, one custom urgent rule, one switched off
//   rules_running  a check running (Run now pressed), the advisor's read-only view
//   rule_editor    the graduation rule: on / off and empty parameters, scope, a preview with its sample
//   alerts         a director's alerts: facets, explanations, flag states, a hidden sensitive alert
//   graduation     the Graduation tab: delayed / at risk / on track / unknown
//   student        the 360 on its "Early warning" section: matches now, the graduation card, recent alerts
//   graduation_cards  the graduation card in every status
//   prefs          the advisor's alert delivery
//   settings       the settings page's "Alerts and nudges" group
//   midterm        the registrar's midterm roster (a locked row)
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/org/advising/adv_alerts_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_flags.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_rules_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_parts.dart';
import 'package:flutter_education_app/features/org/org_registrar_midterm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart';
import '../org/adv_warning_models_test.dart';
import '../org/registrar_midterm_test.dart' show sampleMidtermJson;
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

Widget _host(Widget Function() child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: displayTheme(theme.materialTheme(dark: false), const DisplayPrefs()),
      darkTheme: displayTheme(theme.materialTheme(dark: true), const DisplayPrefs()),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: Builder(builder: (_) => child())),
    ),
  );
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
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
          await tester.pumpWidget(_host(build, dark: dark));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/adv_warning_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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
}

/// A sheet's content as the sheet shows it: padded, at most 640 wide, scrolling.
Widget _sheet(Widget child) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

const _options = AdvPolicyOptions(
  programs: [AdvNamed(id: 4, nameAr: 'هندسة البرمجيات', nameEn: 'Software Engineering')],
  levels: ['Level 1', 'Level 2', 'Level 3'],
  cohorts: ['2023', '2024'],
);

List<AdvCategory> get _cats => [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  AdvRulesView rules({bool canEdit = true, bool running = false}) => AdvRulesView(
        load: AdvLoad.ready,
        bundle: AdvRulesBundle.fromJson(sampleAdvRulesJson(canEdit: canEdit, running: running)),
        options: _options,
        onAdd: () {},
        onOpen: (_) {},
        onToggle: (_, _) {},
        onRunNow: () {},
        onHistory: () {},
      );

  AdvWarningView warning({String graduation = 'delayed'}) => AdvWarningView(
        load: AdvLoad.ready,
        warning: AdvWarning.fromJson(sampleAdvWarningJson(graduation: graduation)),
        onEvaluate: () {},
        onOpenFlag: (_) {},
      );

  AdvAlertsView alerts(String tab) => AdvAlertsView(
        tab: tab,
        manage: true,
        alertsLoad: AdvLoad.ready,
        alerts: AdvPage.fromJson(sampleAdvAlertsJson(), AdvAlert.fromJson),
        gradLoad: AdvLoad.ready,
        graduation: AdvPage.fromJson(sampleAdvGraduationJson(), AdvGraduationItem.fromJson),
        onTab: (_) {},
        onFilters: () {},
        onOpenStudent: (_) {},
        onPropose: (_) {},
        onGradStatus: (_) {},
        onGradSearch: (_) {},
        onOpenGrad: (_) {},
      );

  testWidgets('rules', (t) => _render(t, 'rules', () => Scaffold(body: rules())));
  testWidgets('rules_running', (t) => _render(t, 'rules_running', () => Scaffold(body: rules(canEdit: false, running: true))));
  testWidgets('rule_editor', (t) => _render(t, 'rule_editor', () {
        final b = AdvRulesBundle.fromJson(sampleAdvRulesJson());
        final kind = b.kindOf('graduation_delay')!;
        final d = AdvRuleDraft.of(b.rules[4]);
        return _sheet(AdvRuleEditorView(
          kind: kind,
          draft: d,
          nameAr: TextEditingController(),
          nameEn: TextEditingController(),
          categories: _cats,
          options: _options,
          editing: true,
          system: true,
          preview: AdvRulePreview.fromJson(sampleAdvPreviewJson()),
          onParam: (_, _) {},
          onPriority: (_) {},
          onCooldown: (_) {},
          onCategory: (_) {},
          onScope: (_) {},
          onEnabled: (_) {},
          onPreview: () {},
          onSubmit: () {},
        ));
      }));
  testWidgets('alerts', (t) => _render(t, 'alerts', () => Scaffold(body: alerts('alerts'))));
  testWidgets('graduation', (t) => _render(t, 'graduation', () => Scaffold(body: alerts('graduation'))));
  testWidgets('student', (t) => _render(t, 'student', () {
        return Scaffold(
          body: AdvStudentView(
            load: AdvLoad.ready,
            profile: AdvCaseProfile.fromJson(sampleAdvProfileJson()),
            section: 'warning',
            now: advCaseNow,
            onSection: (_) {},
            flags: AdvFlagsPane(load: AdvLoad.ready, page: AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson), view: 'open', onView: (_) {}, onAlerts: (_) {}),
            warning: warning(),
          ),
        );
      }));
  testWidgets('graduation_cards', (t) => _render(t, 'graduation_cards', () {
        return _sheet(Column(children: [
          for (final s in ['delayed', 'at_risk', 'on_track', 'levels', 'unknown', 'graduated'])
            Padding(padding: const EdgeInsets.only(bottom: 12), child: AdvGraduationCard(graduation: AdvGraduation.fromJson(sampleAdvGraduationBlock(s)))),
        ]));
      }));
  testWidgets('prefs', (t) => _render(t, 'prefs', () => _sheet(AdvAlertPrefsView(prefs: AdvAlertPrefs.fromJson(sampleAdvPrefsJson()), chosen: 'weekly', onChoose: (_) {}, onSave: () {}))));
  testWidgets('settings', (t) => _render(t, 'settings', () {
        final b = AdvPolicyBundle.fromJson({
          'effective': {'digest': 'daily', 'digest_hour': 7, 'digest_weekday': 6, 'nudge_after_days': 21, 'nudge_advisors': true, 'nudge_students': true},
          'defaults': {'digest': 'off', 'digest_hour': 7, 'digest_weekday': 6, 'nudge_after_days': 21, 'nudge_advisors': true, 'nudge_students': true},
          'org': {'id': 1, 'settings': {'digest': 'daily', 'nudge_after_days': 28}},
        });
        return _sheet(AdvAlertSettingsGroup(bundle: b, draft: AdvSettingsDraft.of(b, 'org', null), onField: (_, _) {}, onReset: (_) {}));
      }));
  testWidgets('midterm', (t) => _render(t, 'midterm', () {
        final rows = RegMidtermRoster.fromJson(sampleMidtermJson()).rows;
        return Scaffold(body: RegMidtermList(rows: rows, controllers: {for (final r in rows) if (!r.locked) r.studentId: TextEditingController(text: r.text)}, onSave: () {}));
      }));
}
