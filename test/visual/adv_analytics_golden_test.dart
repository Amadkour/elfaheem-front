// Visual review renders of the Phase 8 advising analytics (D-289, docs/advising/PHASE8.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_analytics_golden_test.dart --update-goldens [--plain-name director]
//
// → test/visual/goldens/adv_an_<scene>_<width>_<lang>_<light|dark>.png at 390×844 (Arabic, light) and 1440×900
// (English, dark).
//   director            the director's dashboard (manage): KPIs, data check, every card
//   director_aggregate  a dean's view: totals only, "Fewer than 5", no chevrons
//   drill               the students behind "High risk"
//   advisors            the advisors table (cards on a phone, a table on a wide screen)
//   composer            the group message composer with its audience preview
//   tracking            one message's delivery and read figures with its recipients
//   student_message     the student's sheet for one message, and the hub block
//   compliance          the compliance report of a term
//   health              the data check with its issues
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
import 'package:flutter_education_app/features/org/advising/adv_advisors_stats_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_analytics_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_analytics_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_drill_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_outreach.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_reports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_analytics_models_test.dart';
import '../org/adv_case_models_test.dart' show advCaseNow, sampleAdvWorkspaceJson;
import '../ui/adv_analytics_layout_test.dart' show director;
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

/// The two renders the owner asked for: a phone in Arabic (light) and a wide screen in English (dark).
const _shots = [(Size(390, 844), 'ar', false), (Size(1440, 900), 'en', true)];

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final (size, lang, dark) in _shots) {
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
        tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
        for (var j = 0; j < 4; j++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      final e = tester.takeException();
      expect(e, isNull, reason: '$name ${size.width.toInt()} $lang: $e');
      await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/adv_an_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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

Widget _sheet(Widget child) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

Widget _page(Widget child) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1240), child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

bool get _ar => AppConfig.lang == 'ar';

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('director', (t) => _render(t, 'director', () => Scaffold(body: director())));
  testWidgets('director_aggregate', (t) => _render(t, 'director_aggregate', () => Scaffold(body: director(aggregate: true))));
  testWidgets('drill', (t) => _render(t, 'drill', () => Scaffold(
        body: AdvDrillView(
          load: AdvLoad.ready,
          title: _ar ? 'خطر مرتفع' : 'High risk',
          filter: const AdvAnalyticsFilter(programId: 11),
          programName: _ar ? 'هندسة البرمجيات' : 'Software Engineering',
          range: AdvOverview.fromJson(sampleAdvOverviewJson()).range,
          page: AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson),
          now: advCaseNow,
          onSearch: (_) {},
          onSort: (_) {},
          onPage: (_) {},
          onOpen: (_) {},
          onMessage: () {},
          onExport: () {},
        ),
      )));
  testWidgets('advisors', (t) => _render(t, 'advisors', () => Scaffold(
        body: AdvAdvisorStatsView(load: AdvLoad.ready, page: AdvPage.fromJson(sampleAdvAdvisorsJson(), AdvAdvisorStat.fromJson), onSearch: (_) {}, onSort: (_) {}, onOpen: (_) {}),
      )));
  testWidgets('composer', (t) => _render(t, 'composer', () => _sheet(AdvOutreachComposerForm(
        subject: TextEditingController(text: _ar ? 'تذكير: مراجعة الخطة الدراسية' : 'Reminder: review your study plan'),
        body: TextEditingController(
            text: _ar ? 'مرحباً {student_name}،\nنرجو حجز لقاء مع مرشدك قبل فتح التسجيل.' : 'Hello {student_name},\nPlease book a meeting with your advisor before registration opens.'),
        preview: AdvOutreachPreview.fromJson(sampleAdvPreviewJson()),
        audienceTitle: 'High risk',
        templates: const [AdvOutreachTemplate(id: 1, nameAr: 'تذكير بالتسجيل', nameEn: 'Registration reminder', bodyAr: 'x')],
        templateId: 1,
        email: true,
        onTemplate: (_) {},
        onToken: (_) {},
        onEmail: (_) {},
        onSend: () {},
      ))));
  testWidgets('tracking', (t) => _render(t, 'tracking', () => Scaffold(
        body: AdvOutreachTrackingView(
          load: AdvLoad.ready,
          outreach: AdvOutreach.fromJson(sampleAdvOutreachJson()),
          recipients: AdvPage.fromJson(sampleAdvRecipientsJson(), AdvOutreachRecipient.fromJson),
          onState: (_) {},
          onSearch: (_) {},
          onPage: (_) {},
          onMessageUnread: () {},
        ),
      )));
  testWidgets('student_message', (t) => _render(t, 'student_message', () => _sheet(Column(children: [
        AdvStudentMessageView(message: AdvStudentMessage.fromJson(sampleAdvStudentMessageJson())),
        const SizedBox(height: 24),
        AdvHubOutreachSection(
          hub: AdvHubOutreach.fromJson({'unread': 1, 'latest': [sampleAdvStudentMessageJson(), sampleAdvStudentMessageJson(read: true)]}),
          onOpen: (_) {},
          onAll: () {},
        ),
      ]))));
  testWidgets('compliance', (t) => _render(t, 'compliance', () => _page(AdvComplianceCard(
        load: AdvLoad.ready,
        report: AdvCompliance.fromJson(sampleAdvComplianceJson()),
        terms: AdvAnalyticsOptions.fromJson(sampleAdvOptionsJson()).terms,
        onExport: (_) {},
        onSchedule: () {},
        onAdvisor: (_) {},
      ))));
  testWidgets('health', (t) => _render(t, 'health', () => _sheet(AdvHealthCard(health: AdvHealth.fromJson(sampleAdvHealthJson()), onRun: () {}, onItem: (_) {}))));
}
