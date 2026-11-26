// The parent group's review-render helpers: the real parent dashboard (or a pushed parent page) over the CAST family
// (test/support/redesign/pa_fakes.dart) inside the app's providers, through the kit's golden host
// (../kit_golden_harness.dart). Not a CI suite.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/parent/pa_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/pa_fakes.dart';
import '../kit_golden_harness.dart';

/// Renders [build] as the CAST parent into `goldens/pa/<name>_<w>_<lang>_light.png`, 390x844 and 1360x900.
Future<void> paRender(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  required StorageService storage,
  FakeApi? api,
  List<String> langs = const ['ar', 'en'],
  bool grow = true,
  bool pushed = false,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  await paSetUp(api ?? paApi());
  AppModeController.applyContext = (_) {};
  await kitRender(
    tester,
    'pa/$name',
    () => MultiProvider(
      providers: appProviders(storage: storage, api: ApiClient()),
      child: pushed ? paRole(build()) : build(),
    ),
    storage: storage,
    langs: langs,
    modes: const [false],
    grow: grow,
    scaffold: false,
    act: act,
  );
}

/// Taps the first widget with [key] (a chip, a tab) and lets it settle a little.
Future<void> paTap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key).first, warnIfMissed: false);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
