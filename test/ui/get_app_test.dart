// The web build's "Get the app" banner: platform detection, webview / PWA / native hiding, the link config, the
// 21-day dismissal and the strip's layout (lib/core/get_app/, lib/features/shared/get_app/get_app_banner.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/get_app/get_app_service.dart';
import 'package:flutter_education_app/features/shared/get_app/get_app_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

// Real user agents (2024 – 2026 browsers).
const _androidPhone =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36';
const _androidTablet =
    'Mozilla/5.0 (Linux; Android 13; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
const _samsungBrowser =
    'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36';
const _androidWebView =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0.0.0 Mobile Safari/537.36';
const _iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const _iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 Mobile/15E148 Safari/604.1';
const _iphoneWkWebView =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const _iphoneFacebook =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/470.0.0.40.97]';
const _ipadOld =
    'Mozilla/5.0 (iPad; CPU OS 12_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1';
const _macSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const _macFirefox = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:131.0) Gecko/20100101 Firefox/131.0';
const _windowsEdge =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0';
const _linuxFirefox = 'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0';
const _ubuntuChrome =
    'Mozilla/5.0 (X11; Ubuntu; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
const _chromeOs =
    'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
const _tizenTv =
    'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0 TV Safari/537.36';
const _xbox =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36 Edge/44.18363.8131';
const _fireTv =
    'Mozilla/5.0 (Linux; Android 9; AFTMM Build/PS7233) AppleWebKit/537.36 (KHTML, like Gecko) Silk/112.3.1 like Chrome/112.0 Safari/537.36';

const _allLinks = {
  'android': 'https://play.google.com/store/apps/details?id=x.y',
  'ios': 'https://apps.apple.com/app/id1',
  'windows': 'https://example.org/app.msix',
  'macos': 'https://example.org/app.dmg',
  'linux': 'https://example.org/app.AppImage',
};

GetAppEnv _web(GetAppOs os, {bool standalone = false, bool embedded = false}) =>
    GetAppEnv(isWeb: true, os: os, standalone: standalone, embedded: embedded);

void main() {
  group('detectGetAppOs', () {
    test('phones and tablets', () {
      expect(detectGetAppOs(_androidPhone), GetAppOs.android);
      expect(detectGetAppOs(_androidTablet), GetAppOs.android, reason: 'a tablet has no "Mobile" but is Android');
      expect(detectGetAppOs(_samsungBrowser), GetAppOs.android);
      expect(detectGetAppOs(_iphoneSafari), GetAppOs.ios, reason: '"like Mac OS X" must not make it a Mac');
      expect(detectGetAppOs(_iphoneChrome), GetAppOs.ios);
      expect(detectGetAppOs(_ipadOld), GetAppOs.ipados);
    });

    test('iPadOS 13+ reports a Mac: touch points tell them apart', () {
      expect(detectGetAppOs(_macSafari, maxTouchPoints: 5), GetAppOs.ipados);
      expect(detectGetAppOs(_macSafari, maxTouchPoints: 0), GetAppOs.macos);
      expect(detectGetAppOs(_macSafari, maxTouchPoints: 1), GetAppOs.macos, reason: 'one point is not an iPad');
      expect(detectGetAppOs(_macFirefox), GetAppOs.macos);
    });

    test('desktops', () {
      expect(detectGetAppOs(_windowsEdge), GetAppOs.windows);
      expect(detectGetAppOs(_linuxFirefox), GetAppOs.linux);
      expect(detectGetAppOs(_ubuntuChrome), GetAppOs.linux);
    });

    test('Android is never Linux, even though its UA says "Linux"', () {
      expect(_androidPhone.contains('Linux'), isTrue);
      expect(detectGetAppOs(_androidPhone), isNot(GetAppOs.linux));
    });

    test('unknown, TVs, consoles and ChromeOS get no link', () {
      expect(detectGetAppOs(''), GetAppOs.other);
      expect(detectGetAppOs('curl/8.4.0'), GetAppOs.other);
      expect(detectGetAppOs(_chromeOs), GetAppOs.other);
      expect(detectGetAppOs(_tizenTv), GetAppOs.other);
      expect(detectGetAppOs(_xbox), GetAppOs.other);
      expect(detectGetAppOs(_fireTv), GetAppOs.other);
    });
  });

  test('looksLikeInAppWebView', () {
    expect(looksLikeInAppWebView(_androidWebView), isTrue);
    expect(looksLikeInAppWebView(_iphoneWkWebView), isTrue);
    expect(looksLikeInAppWebView(_iphoneFacebook), isTrue);
    for (final ua in [_androidPhone, _androidTablet, _iphoneSafari, _iphoneChrome, _ipadOld, _macSafari, _macFirefox,
      _windowsEdge, _linuxFirefox]) {
      expect(looksLikeInAppWebView(ua), isFalse, reason: ua);
    }
  });

  group('parseGetAppLinks', () {
    test('keeps https links, drops empty / http / junk', () {
      final l = parseGetAppLinks({
        'android': ' https://play.google.com/store/apps/details?id=x.y ',
        'ios': '',
        'windows': 'http://example.org/app.exe',
        'macos': 42,
        'linux': 'not a url',
        'other': 'https://example.org',
      });
      expect(l.linkFor(GetAppOs.android), 'https://play.google.com/store/apps/details?id=x.y');
      expect(l.linkFor(GetAppOs.ios), isNull);
      expect(l.linkFor(GetAppOs.windows), isNull);
      expect(l.linkFor(GetAppOs.macos), isNull);
      expect(l.linkFor(GetAppOs.linux), isNull);
      expect(l.linkFor(GetAppOs.other), isNull);
    });

    test('iPad uses the App Store link; not a map → nothing', () {
      expect(parseGetAppLinks(_allLinks).linkFor(GetAppOs.ipados), 'https://apps.apple.com/app/id1');
      expect(parseGetAppLinks(null).isEmpty, isTrue);
      expect(parseGetAppLinks('<html>').isEmpty, isTrue);
      expect(parseGetAppLinks([1, 2]).isEmpty, isTrue);
    });
  });

  group('shouldShowGetAppBanner', () {
    final links = parseGetAppLinks(_allLinks);
    final now = DateTime(2026, 10, 31, 12);

    test('a browser tab with a link: shown', () {
      for (final os in GetAppOs.values.where((o) => o != GetAppOs.other)) {
        expect(shouldShowGetAppBanner(env: _web(os), links: links, now: now), isTrue, reason: '$os');
      }
    });

    test('native app, installed PWA, in-app browser, unknown device: hidden', () {
      expect(shouldShowGetAppBanner(env: GetAppEnv.native, links: links, now: now), isFalse);
      expect(shouldShowGetAppBanner(env: _web(GetAppOs.android, standalone: true), links: links, now: now), isFalse);
      expect(shouldShowGetAppBanner(env: _web(GetAppOs.ios, embedded: true), links: links, now: now), isFalse);
      expect(shouldShowGetAppBanner(env: _web(GetAppOs.other), links: links, now: now), isFalse);
      expect(getAppEntryAvailable(_web(GetAppOs.android, standalone: true), links), isFalse);
    });

    test('no link for this device: hidden (banner and settings row)', () {
      final onlyAndroid = parseGetAppLinks({'android': _allLinks['android']});
      expect(shouldShowGetAppBanner(env: _web(GetAppOs.windows), links: onlyAndroid, now: now), isFalse);
      expect(getAppEntryAvailable(_web(GetAppOs.windows), onlyAndroid), isFalse);
      expect(getAppEntryAvailable(_web(GetAppOs.android), onlyAndroid), isTrue);
      expect(shouldShowGetAppBanner(env: _web(GetAppOs.android), links: GetAppLinks.none, now: now), isFalse);
    });

    test('dismissed: hidden for 21 days, then back', () {
      final env = _web(GetAppOs.android);
      bool show(DateTime at) => shouldShowGetAppBanner(env: env, links: links, now: now, dismissedAt: at);
      expect(show(now), isFalse);
      expect(show(now.subtract(const Duration(days: 20, hours: 23))), isFalse);
      expect(show(now.subtract(const Duration(days: 21))), isTrue);
      expect(show(now.add(const Duration(hours: 2))), isFalse, reason: 'small clock skew still counts');
      expect(show(now.add(const Duration(days: 300))), isTrue, reason: 'a stamp far in the future is ignored');
      // the settings row ignores the dismissal
      expect(getAppEntryAvailable(env, links), isTrue);
    });
  });

  test('routes: only the role homes', () {
    for (final r in ['/dashboard', '/teacher_dashboard', '/admin_dashboard', '/parent_dashboard', '/org_dashboard']) {
      expect(routeAllowsGetAppBanner(r), isTrue, reason: r);
    }
    for (final r in [null, '/login', '/register', '/otp', '/forgot-password', '/course-detail', '/downloads',
      '/attendance-live', '/live/abc', '/calendar']) {
      expect(routeAllowsGetAppBanner(r), isFalse, reason: '$r');
    }
  });

  group('GetAppService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    GetAppService service(GetAppEnv env, {Object? links = _allLinks, DateTime? at}) => GetAppService(
          env: () => env,
          loadLinks: () async => links,
          clock: () => at ?? DateTime(2026, 10, 31, 12),
        );

    test('loads links and remembers a dismissal across instances', () async {
      final a = service(_web(GetAppOs.ios));
      await a.init();
      expect(a.bannerEligible, isTrue);
      expect(a.link, 'https://apps.apple.com/app/id1');
      await a.dismiss();
      expect(a.bannerEligible, isFalse);
      expect(a.entryAvailable, isTrue, reason: 'the settings row stays');

      final b = service(_web(GetAppOs.ios), at: DateTime(2026, 11, 10));
      await b.init();
      expect(b.bannerEligible, isFalse, reason: '10 days later');
      final c = service(_web(GetAppOs.ios), at: DateTime(2026, 11, 22));
      await c.init();
      expect(c.bannerEligible, isTrue, reason: '22 days later');
    });

    test('native / standalone / missing or broken config: nothing', () async {
      for (final s in [
        service(GetAppEnv.native),
        service(_web(GetAppOs.android, standalone: true)),
        service(_web(GetAppOs.android, embedded: true)),
        service(_web(GetAppOs.linux), links: null),
        service(_web(GetAppOs.linux), links: const {'linux': ''}),
      ]) {
        await s.init();
        expect(s.bannerEligible, isFalse);
        expect(s.entryAvailable, isFalse);
        expect(s.link, isNull);
      }
      final broken = GetAppService(
        env: () => _web(GetAppOs.android),
        loadLinks: () async => throw const FormatException('index.html is not JSON'),
      );
      await broken.init();
      expect(broken.entryAvailable, isFalse);
    });
  });

  group('GetAppBannerView', () {
    setUp(() => AppConfig.lang = 'ar');

    testWidgets('no overflow at 320 / 1400, ar / en, text x1.3, every platform', (tester) async {
      for (final os in GetAppOs.values.where((o) => o != GetAppOs.other)) {
        await expectNoLayoutErrors(
          tester,
          () => Align(
            alignment: Alignment.topCenter,
            child: GetAppBannerView(os: os, onOpen: () {}, onDismiss: () {}),
          ),
        );
      }
    });

    testWidgets('one store button, a 48 px close target, taps reach the callbacks', (tester) async {
      var opened = 0, dismissed = 0;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(layoutHost(Align(
        alignment: Alignment.topCenter,
        child: GetAppBannerView(os: GetAppOs.android, onOpen: () => opened++, onDismiss: () => dismissed++),
      )));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(getAppButtonLabel(GetAppOs.android)), findsOneWidget);
      final close = find.bySemanticsLabel(translate('get_app_dismiss'));
      expect(close, findsOneWidget);
      final size = tester.getSize(close);
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: '$size');
      await tester.tap(find.byType(FilledButton));
      await tester.tap(close);
      expect((opened, dismissed), (1, 1));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });
}
