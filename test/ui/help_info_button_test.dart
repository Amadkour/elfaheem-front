// HelpInfoButton (f3): hidden without an entry / with the kill switch, opens the sheet, layout at every size.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/features/shared/help/help_info_button.dart';
import 'package:flutter_education_app/features/shared/help/help_models.dart';
import 'package:flutter_education_app/features/shared/help/help_service.dart';
import 'package:flutter_education_app/features/shared/help/help_tour.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

class _Remote implements HelpRemote {
  final Map<String, dynamic> entry = jsonDecode(File('test/fixtures/help_entry_home_student.json').readAsStringSync());
  int calls = 0;
  @override
  Future<int?> version({String? etag}) async {
    calls++;
    return null;
  }

  @override
  Future<Map<String, dynamic>> pages({int? orgId}) async {
    calls++;
    return {'version': 1, 'role': 'student', 'pages': [entry]};
  }
}

HelpEntry _entry() => HelpEntry.fromJson(jsonDecode(File('test/fixtures/help_entry_home_student.json').readAsStringSync()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = helpUserKeyOf;
  late _Remote remote;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    helpUserKeyOf = (_) => '7';
    remote = _Remote();
    HelpService.debugReplace(HelpService(remote: remote));
  });
  tearDown(() {
    helpUserKeyOf = saved;
    AppConfig.setDisableList(const []);
  });

  Future<void> pumpButton(WidgetTester tester, String id) async {
    await tester.runAsync(() => HelpService.instance.loadIndex()); // the bundled asset is read in the real zone
    await tester.pumpWidget(layoutHost(Center(child: HelpInfoButton(pageId: id, autoTour: false))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shown when the server has an entry for the page', (tester) async {
    await pumpButton(tester, 'home.student');
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('About this page'), findsWidgets);
    final size = tester.getSize(find.byType(ChromeIconButton));
    expect(size.width >= 48 && size.height >= 48, isTrue);
  });

  testWidgets('shown from the bundled index with no request at all', (tester) async {
    await pumpButton(tester, 'home.student');
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(remote.calls, 0);
    expect(HelpService.instance.entry('home.student'), isNull); // no content, so no tour either
  });

  testWidgets('hidden when there is no entry for the page', (tester) async {
    await pumpButton(tester, 'no.such.page');
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });

  testWidgets('hidden for a guest / signed-out person', (tester) async {
    helpUserKeyOf = (_) => null;
    await pumpButton(tester, 'home.student');
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });

  testWidgets('hidden by the help.info kill switch', (tester) async {
    AppConfig.setDisableList(const ['help.info']);
    await pumpButton(tester, 'home.student');
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });

  testWidgets('tap opens the sheet with title, summary, items and the actions', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpButton(tester, 'home.student');
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ask about this page'), findsOneWidget);
    expect(find.text('Take the tour'), findsOneWidget);
    expect(find.text('Live or next session'), findsOneWidget);
    expect(remote.calls, 1); // the tap fetched the catalogue
  });

  testWidgets('HelpEntryView has no layout error at any size / language / text scale', (tester) async {
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: HelpEntryView(entry: _entry(), onClose: () {}, onAsk: () {}, onTour: () {})));
  });

  testWidgets('the wide side panel and the phone sheet have no layout error', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) => TextButton(onPressed: () => showHelpFor(context, _entry()), child: const Text('open'))),
      act: (t) async {
        await t.tap(find.text('open'));
      },
    );
  });

  testWidgets('tour overlay: skips missing targets, Skip always there, no layout error', (tester) async {
    final steps = _entry().tour; // live_card, needs_you, search, tabs
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        const HelpTourTarget(pageId: 'home.student', id: 'search', child: SizedBox(width: 120, height: 48, child: Text('search box'))),
        const HelpTourTarget(pageId: 'home.student', id: 'tabs', child: SizedBox(width: 120, height: 48, child: Text('tabs'))),
        Builder(builder: (context) => TextButton(onPressed: () => runHelpTour(context, steps, pageId: 'home.student'), child: const Text('go'))),
      ]),
      act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 100));
        final ar = AppConfig.lang == 'ar';
        expect(find.text(ar ? 'تخطي' : 'Skip'), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget); // only the two wired targets are on screen
        await t.tap(find.text(ar ? 'التالي' : 'Next'));
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text(ar ? 'تم' : 'Done'), findsOneWidget);
        await t.tap(find.text(ar ? 'تخطي' : 'Skip'));
      },
    );
  });
}
