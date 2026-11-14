// F15: the start-up version check against GET /app/version-check, through ApiClient over a fake backend:
// - must_update → the blocking dialog (no "Later", back does nothing);
// - should_update → the gentle dialog with "Later";
// - up to date → nothing;
// - the API unreachable → nothing (the app never blocks on a dead network), unless a refused certificate pin of our
//   own host was seen, which is itself a reason to update (D-946).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/cert_pin.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

void main() {
  late FakeApi api;
  late Object? Function(RequestOptions o) answer;

  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    CertPin.updateRequired = false;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    PackageInfo.setMockInitialValues(
        appName: 'NextBrain', packageName: 'com.doubley.nextbrain', version: '1.0.0', buildNumber: '10', buildSignature: '');
    api = FakeApi({'GET /api/app/version-check': (o) => answer(o)}, latency: const Duration(milliseconds: 10))..install();
  });

  tearDown(() {
    api.uninstall();
    CertPin.updateRequired = false;
  });

  Future<void> run(WidgetTester tester) async {
    await tester.pumpWidget(ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    ));
    unawaited(VersionCheckService.instance.debugCheck('android'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  UpdateDialog? dialog(WidgetTester tester) {
    final f = find.byType(UpdateDialog);
    return f.evaluate().isEmpty ? null : tester.widget<UpdateDialog>(f);
  }

  const link = 'https://nextbrain.site/api/v1/app/downloads/app.apk';

  testWidgets('must_update → a blocking dialog without "Later"', (tester) async {
    answer = (_) => {'must_update': true, 'should_update': true, 'latest_version': '2.0.0', 'download_url': link};
    await run(tester);
    final d = dialog(tester);
    expect(d, isNotNull);
    expect(d!.force, isTrue);
    expect(find.byType(TextButton), findsNothing); // no Later
    expect(api.calls.single.query['platform'], 'android');
    expect(api.calls.single.query['version'], '1.0.0');
    // back does not close it
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(dialog(tester), isNotNull);
  });

  testWidgets('should_update → a dialog with "Later", which closes it', (tester) async {
    answer = (_) => {'must_update': false, 'should_update': true, 'latest_version': '2.0.0', 'download_url': link};
    await run(tester);
    final d = dialog(tester);
    expect(d, isNotNull);
    expect(d!.force, isFalse);
    expect(d.version, '2.0.0');
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(dialog(tester), isNull);
    // snoozed for that version
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_prompt_later_v1'), startsWith('v2.0.0:'));
  });

  testWidgets('up to date → nothing', (tester) async {
    answer = (_) => {'must_update': false, 'should_update': false};
    await run(tester);
    expect(dialog(tester), isNull);
  });

  testWidgets('the API unreachable → nothing, the app is never blocked by a dead network', (tester) async {
    answer = (o) => throw DioException.connectionError(requestOptions: o, reason: 'unreachable');
    await run(tester);
    expect(api.calls, hasLength(1));
    expect(dialog(tester), isNull);
  });

  testWidgets('unreachable after a refused pin of our own host → the blocking "update the app" dialog', (tester) async {
    CertPin.updateRequired = true;
    answer = (o) => throw DioException.connectionError(requestOptions: o, reason: 'pin');
    await run(tester);
    final d = dialog(tester);
    expect(d, isNotNull);
    expect(d!.force, isTrue);
    expect(d.message, isNotEmpty);
  });
}
