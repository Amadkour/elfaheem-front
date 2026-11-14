// Visual review renders of the Phase 3 advising pages (D-289, docs/advising/PHASE3.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_assign_golden_test.dart --update-goldens [--plain-name advisors]
//
// → test/visual/goldens/adv_assign_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   config_org       the organization's settings with one department override
//   config_scope     a department's own settings, one field changed (Save shows)
//   advisors         the advisors with loads, statuses and the over-capacity banner
//   profile_sheet    an advisor on leave: dates, own maximum, contact, conflicts
//   my_profile       an advisor's own page
//   distribute       the distribution preview: counts, warnings, before → after, the first moves, the runs
//   reassign         reassign mode for an advisor on leave
//   students         students with their advisors and the filters
//   student_sheet    a student's advisors (several allowed) with "assign anyway"
//   handovers        handovers to acknowledge
//   setup_links      the advising page of a director who also advises: the counts, the banners, the links
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
import 'package:flutter_education_app/features/org/advising/adv_advisors_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_config_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_distribute_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_handovers_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_students_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_assign_models_test.dart';
import '../org/adv_models_test.dart' show sampleAdvStatusJson;
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();


Widget _host(Widget Function() child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
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
            matchesGoldenFile('goldens/adv_assign_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

AdvPolicyBundle get _bundle => AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
AdvPage<AdvAdvisor> get _advisors => AdvPage.fromJson(sampleAdvAdvisorsJson(), AdvAdvisor.fromJson);
AdvPage<AdvStudent> get _students => AdvPage.fromJson(sampleAdvStudentsJson(), AdvStudent.fromJson);

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  final note = TextEditingController(text: 'Office hours: Sunday and Tuesday 10:00–12:00');
  final office = TextEditingController(text: 'Building B, room 214');
  final empty = TextEditingController();

  AdvConfigView config(AdvSettingsDraft draft) => AdvConfigView(
        load: AdvLoad.ready,
        bundle: _bundle,
        draft: draft,
        onScope: (_) {},
        onField: (_, _) {},
        onReset: (_) {},
        onSave: () {},
        onAddScope: () {},
        onRemoveScope: () {},
        onInheritAll: () {},
      );

  AdvDistributeView dist(AdvPlanRequest request, {AdvPlan? plan}) => AdvDistributeView(
        request: request,
        options: _bundle.options,
        settingsStrategy: 'balanced',
        plan: plan,
        runs: AdvPage.fromJson(sampleAdvRunsJson(), AdvRun.fromJson),
        force: plan != null,
        forceReason: TextEditingController(text: 'No other advisors in the program this term'),
        onForce: (_) {},
        onRequest: (_) {},
        onPickFrom: () {},
        onPickTo: () {},
        onPreview: () {},
        onApply: () {},
      );

  testWidgets('config_org', (t) => _render(t, 'config_org', () => Scaffold(body: config(AdvSettingsDraft.of(_bundle, 'org', null)))));
  testWidgets(
      'config_scope',
      (t) => _render(t, 'config_scope',
          () => Scaffold(body: config(AdvSettingsDraft.of(_bundle, 'dept', '21').set('eligible_ranks', ['professor', 'associate_professor'])))));
  testWidgets(
      'advisors',
      (t) => _render(
          t,
          'advisors',
          () => Scaffold(
                body: AdvAdvisorsView(
                    load: AdvLoad.ready, page: _advisors, onSearch: (_) {}, onStatus: (_) {}, onSort: (_) {}, onOpen: (_) {}, onDistribute: () {}),
              )));
  testWidgets('profile_sheet', (t) => _render(t, 'profile_sheet', () {
        final leila = _advisors.items[2];
        return _sheet(AdvProfileForm(
          advisor: leila,
          draft: AdvProfileDraft.of(leila).copyWith(maxLoadOverride: () => 25),
          manage: true,
          office: office,
          contact: note,
          bio: empty,
          conflicts: AdvPage.fromJson(sampleAdvConflictsJson(), AdvConflict.fromJson).items,
          onDraft: (_) {},
          onSubmit: () {},
          onPickFrom: () {},
          onPickUntil: () {},
          onReassign: () {},
          onAddConflict: () {},
          onRemoveConflict: (_) {},
        ));
      }));
  testWidgets('my_profile',
      (t) => _render(t, 'my_profile', () => Scaffold(body: AdvMyProfileView(load: AdvLoad.ready, me: _advisors.items.first, onEdit: () {}))));
  testWidgets('distribute',
      (t) => _render(t, 'distribute', () => Scaffold(body: dist(const AdvPlanRequest(), plan: AdvPlan.fromJson(sampleAdvPlanJson())))));
  testWidgets(
      'reassign',
      (t) => _render(
          t,
          'reassign',
          () => Scaffold(
                body: dist(AdvPlanRequest(mode: 'reassign', from: AdvRef(userId: 33, name: AppConfig.lang == 'ar' ? 'د. ليلى منصور' : 'Dr. Leila Mansour'))),
              )));
  testWidgets(
      'students',
      (t) => _render(
          t,
          'students',
          () => Scaffold(
                body: AdvStudentsView(
                    load: AdvLoad.ready,
                    manage: true,
                    page: _students,
                    onSearch: (_) {},
                    onFilter: (_) {},
                    onPage: (_) {},
                    onOpen: (_) {},
                    onDistribute: () {}),
              )));
  testWidgets('student_sheet', (t) => _render(t, 'student_sheet', () {
        final s = _students.items[1];
        return _sheet(AdvStudentForm(
          student: s,
          draft: AdvAdvisorsDraft.of(s).copyWith(primary: () => const AdvRef(userId: 34, name: 'Dr. Samir Adel'), force: true),
          multi: true,
          manage: true,
          reason: empty,
          overCapacity: true,
          history: [for (final m in (sampleAdvHistoryJson()['items'] as List).cast<Map<String, dynamic>>()) AdvHistoryEntry.fromJson(m)],
          conflicts: const [],
          onPickPrimary: () {},
          onClearPrimary: () {},
          onLocked: (_) {},
          onAddOther: (_) {},
          onRemoveOther: (_) {},
          onForce: (_) {},
          onSubmit: () {},
          onAddConflict: () {},
        ));
      }));
  testWidgets(
      'handovers',
      (t) => _render(
          t,
          'handovers',
          () => Scaffold(
                body: AdvHandoversView(
                  load: AdvLoad.ready,
                  page: AdvPage.fromJson(sampleAdvHandoversJson(), AdvHandover.fromJson),
                  me: 32,
                  pendingOnly: false,
                  onPending: (_) {},
                  onAck: (_) {},
                ),
              )));
  testWidgets(
      'setup_links',
      (t) => _render(
          t,
          'setup_links',
          () => Scaffold(
                body: AdvSetupView(
                  state: AdvSetupState.on,
                  deptName: AppConfig.lang == 'ar' ? 'الإرشاد الأكاديمي' : 'Academic Advising',
                  status: AdvStatus.fromJson({
                    ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
                    'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'handovers_pending': 3},
                    'counts': {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14, 'away': 22, 'over': 1},
                  }),
                  onOpen: (_) {},
                  onDisable: () {},
                ),
              )));
}
