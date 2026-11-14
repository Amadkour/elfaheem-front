// The website channel's download strip (D-144, lib/core/release/app_downloads.dart + get_app/app_download_banner.dart):
//   • the list: web and file-less entries dropped, a server path read against the API base, the server's `primary`
//   • what each device is offered: Android → the universal APK (arm64 / v7a under "other downloads"), Windows → the zip,
//     Linux → the .deb, iPhone / iPad → Add to Home Screen, a Mac → "see downloads"; nothing in an installed web app, a
//     wrapper, an Android in-app browser, or with an empty list
//   • closing it is remembered on this browser for this version; a new version shows it again
//   • the kill switch `app.download_banner`, a failed request and an empty list hide it
//   • the strip in the app: the reload strip of D-143 above it, both visible; "Other downloads" opens the sheet
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/release/web_release_watch.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_text.dart' show releaseErrorText;
import 'package:flutter_education_app/features/get_app/app_download_banner.dart';
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppBannerView;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_releases_samples.dart';
import 'layout_harness.dart';

const _api = 'https://alfheemacademy.com/api';

GetAppEnv _web(GetAppOs os, {bool standalone = false, bool embedded = false, bool inApp = false}) =>
    GetAppEnv(isWeb: true, os: os, standalone: standalone, embedded: embedded, inAppBrowser: inApp, iosSafari: os == GetAppOs.ios);

AppDownloadsService _service({
  GetAppOs os = GetAppOs.android,
  Object? Function()? answer,
  Set<String> off = const {},
}) =>
    AppDownloadsService(
      env: () => _web(os),
      fetch: () async => (answer ?? () => downloadsJson())(),
      disabled: off.contains,
      apiBase: _api,
    );

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  final list = parseAppDownloads(downloadsJson(), apiBase: _api);

  test('the list: web and empty entries dropped, server paths made absolute, the server picks the main file', () {
    final raw = [
      ...downloadsJson(),
      {'platform': 'web', 'version': '1.4.1', 'files': [{'name': 'web.zip', 'url': 'https://x/web.zip'}]},
      {'platform': 'macos', 'version': '1.0.0', 'files': []},
      {
        'platform': 'ios',
        'version': '1.0.0',
        'files': [{'name': 'x.ipa', 'url': '/api/v1/app/downloads/ios/x.ipa', 'size': 10}],
      },
    ];
    final r = parseAppDownloads({'items': raw}, apiBase: _api);
    expect([for (final x in r) x.platform], ['android', 'windows', 'linux', 'ios'], reason: 'the sheet order; no web, no empty macOS');
    expect(r.last.files.single.url, 'https://alfheemacademy.com/api/api/v1/app/downloads/ios/x.ipa');
    final android = r.first;
    expect(android.primary!.abi, 'universal');
    expect([for (final f in android.others) f.abi], ['arm64-v8a', 'armeabi-v7a']);
    expect(r[2].primary!.kind, 'deb');
    expect(parseAppDownloads('<html>', apiBase: _api), isEmpty);
    // no `primary` from an older answer: the universal APK still wins
    final old = parseAppDownloads([
      {
        'platform': 'android',
        'version': '1.0.0',
        'files': [
          {'name': 'Alfaheem-1.0.0-1-arm64-v8a.apk', 'url': 'https://x/a.apk'},
          {'name': 'Alfaheem-1.0.0-1-universal.apk', 'url': 'https://x/u.apk'},
        ],
      },
    ], apiBase: _api);
    expect(old.single.primary!.name, contains('universal'));
  });

  test('what each device is offered', () {
    final a = appDownloadOfferFor(_web(GetAppOs.android), list)!;
    expect(a.kind, AppDownloadOfferKind.file);
    expect(a.file!.name, 'Alfaheem-1.4.1-53-universal.apk');
    expect(a.stamp, 'android:1.4.1+53');
    expect(appDownloadOfferFor(_web(GetAppOs.windows), list)!.file!.kind, 'zip');
    expect(appDownloadOfferFor(_web(GetAppOs.linux), list)!.file!.kind, 'deb');
    expect(appDownloadOfferFor(_web(GetAppOs.ios), list)!.kind, AppDownloadOfferKind.iosWebApp);
    expect(appDownloadOfferFor(_web(GetAppOs.ipados), list)!.kind, AppDownloadOfferKind.iosWebApp);
    expect(appDownloadOfferFor(_web(GetAppOs.macos), list)!.kind, AppDownloadOfferKind.browse);
    expect(appDownloadOfferFor(_web(GetAppOs.other), list)!.kind, AppDownloadOfferKind.browse);
    // a platform with nothing of its own: the list
    expect(appDownloadOfferFor(_web(GetAppOs.windows), [list.first])!.kind, AppDownloadOfferKind.browse);
    // nothing to offer
    expect(appDownloadOfferFor(_web(GetAppOs.android, standalone: true), list), isNull, reason: 'the installed web app');
    expect(appDownloadOfferFor(_web(GetAppOs.android, embedded: true), list), isNull, reason: 'a native wrapper');
    expect(appDownloadOfferFor(_web(GetAppOs.android, inApp: true), list), isNull, reason: 'an in-app browser cannot install an APK');
    expect(appDownloadOfferFor(GetAppEnv.native, list), isNull);
    expect(appDownloadOfferFor(_web(GetAppOs.android), const []), isNull);
    expect(appDownloadOfferFor(_web(GetAppOs.ios), const []), isNull, reason: 'an empty list hides the strip everywhere');
  });

  test('closed for this version, back for the next one; remembered on the browser', () async {
    final s = _service();
    await s.init();
    expect(s.visible, isTrue);
    await s.dismiss();
    expect(s.visible, isFalse);
    expect((await SharedPreferences.getInstance()).getString(kDownloadBannerDismissedKey), 'android:1.4.1+53');

    // the next visit of the same browser, same version: still closed
    final again = _service();
    await again.init();
    expect(again.visible, isFalse);

    // a new Android version: shown again
    final next = _service(answer: () => downloadsJson(androidVersion: '1.4.2', androidBuild: 54));
    await next.init();
    expect(next.visible, isTrue);
  });

  test('kill switch, a failed request, an empty list', () async {
    final off = _service(off: {kDownloadBannerKey});
    await off.init();
    expect(off.offer, isNotNull);
    expect(off.visible, isFalse);

    final failed = _service(answer: () => throw const HttpException('503'));
    await failed.init();
    expect(failed.loaded, isTrue);
    expect(failed.visible, isFalse);
    expect(failed.hasDownloads, isFalse);

    final empty = _service(answer: () => const []);
    await empty.init();
    expect(empty.visible, isFalse);

    final native = AppDownloadsService(env: () => GetAppEnv.native, fetch: () async => downloadsJson(), disabled: (_) => false);
    await native.init();
    expect(native.visible, isFalse, reason: 'the native app has its own update prompt');
  });

  test('a Codemagic failure reads as a sentence', () {
    AppConfig.lang = 'en';
    expect(releaseErrorText('codemagic_start_failed: Codemagic refused the API token (check CODEMAGIC_API_TOKEN)', 'x'),
        'Codemagic did not start the build: Codemagic refused the API token (check CODEMAGIC_API_TOKEN)');
    expect(releaseErrorText('upload_missing: the build finished but did not finish uploading its files', 'x'), contains('upload to our server'));
  });

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('in the app: under the reload strip (both show), Other downloads opens the sheet, close hides it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final s = _service();
    final bus = LiveEvents.instance;
    final watch = WebReleaseWatch(bus: bus, running: ('1.4.0', 52), reload: () {});
    addTearDown(watch.dispose);
    var sheets = 0;
    await tester.pumpWidget(layoutHost(
      WebReleaseBanner(
        enabled: true,
        watch: watch,
        child: AppDownloadBanner(enabled: true, service: s, openSheet: (_) => sheets++, child: const Scaffold(body: Text('page'))),
      ),
      scale: 1,
      scaffold: false,
    ));
    await frames(tester);
    expect(find.text('Get the Android app'), findsOneWidget);
    expect(find.textContaining('96'), findsOneWidget, reason: 'the size of the universal APK');

    bus.emit(LiveEvents.appReleaseLive, {'platform': 'web', 'version': '1.4.1', 'build_number': 53, 'policy': 'recommended'});
    await frames(tester);
    final reload = tester.getTopLeft(find.byType(WebReleaseStrip)).dy;
    final download = tester.getTopLeft(find.text('Get the Android app')).dy;
    expect(reload, lessThan(download), reason: 'the reload strip keeps the top spot');

    await tester.tap(find.text('Get the Android app'));
    await frames(tester);
    expect(sheets, 1, reason: 'on a phone the text opens the downloads');

    await tester.tap(find.descendant(of: find.byType(GetAppBannerView), matching: find.byIcon(Icons.close_rounded)));
    await frames(tester);
    expect(find.text('Get the Android app'), findsNothing);
    expect(find.text('page'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the kill switch hides the strip in the app', (tester) async {
    AppConfig.disableList = [kDownloadBannerKey];
    final s = AppDownloadsService(env: () => _web(GetAppOs.windows), fetch: () async => downloadsJson(), apiBase: _api);
    await tester.pumpWidget(layoutHost(AppDownloadBanner(enabled: true, service: s, child: const Text('page')), scale: 1));
    await frames(tester);
    expect(find.text('Get the Windows app'), findsNothing);
    AppConfig.setDisableList(const []);
    await frames(tester);
    expect(find.text('Get the Windows app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the sheet: this device first, the other files and platforms under Other downloads', (tester) async {
    final downloaded = <String>[];
    final offer = appDownloadOfferFor(_web(GetAppOs.android), list);
    await tester.pumpWidget(layoutHost(
      SingleChildScrollView(child: AppDownloadsSheetBody(releases: list, offer: offer, onDownload: (f) => downloaded.add(f.name))),
      scale: 1,
    ));
    await frames(tester, 3);
    expect(find.byKey(const ValueKey('app_dl.device')), findsOneWidget);
    expect(find.text('Other downloads'), findsOneWidget);
    expect(find.byKey(const ValueKey('app_dl.platform.windows')), findsOneWidget);
    expect(find.byKey(const ValueKey('app_dl.platform.linux')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app_dl.file.Alfaheem-1.4.1-53-universal.apk')));
    final v7a = find.byKey(const ValueKey('app_dl.file.Alfaheem-1.4.1-53-armeabi-v7a.apk'));
    await tester.ensureVisible(v7a);
    await tester.tap(v7a);
    expect(downloaded, ['Alfaheem-1.4.1-53-universal.apk', 'Alfaheem-1.4.1-53-armeabi-v7a.apk']);

    // iPhone: the Add to Home Screen steps
    await tester.pumpWidget(layoutHost(
      SingleChildScrollView(
          child: AppDownloadsSheetBody(releases: list, offer: appDownloadOfferFor(_web(GetAppOs.ios), list), onDownload: (_) {})),
      scale: 1,
    ));
    await frames(tester, 3);
    expect(find.byKey(const ValueKey('app_dl.ios')), findsOneWidget);
    expect(find.text('Choose "Add to Home Screen".'), findsOneWidget);
  });
}
