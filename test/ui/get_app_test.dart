// "Get the app" / direct downloads: platform detection (iPadOS-as-Mac, in-app browsers, standalone), the releases
// manifest, what each browser is offered, the 14-day dismissal, the kill switches, the light analytics, the native
// update rule, and the layouts of the strip, the sheet and the update dialog (lib/core/get_app/,
// lib/features/get_app/, lib/core/version_check_service.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/get_app/get_app_service.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/features/get_app/get_app_banner.dart';
import 'package:flutter_education_app/features/get_app/get_app_sheet.dart';
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
const _androidInstagram =
    'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36 Instagram 350.0.0.0 Android';
const _iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const _iphoneSafari26 =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1';
const _iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 Mobile/15E148 Safari/604.1';
const _iphoneEdge =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 EdgiOS/129.0.2792.84 Mobile/15E148 Safari/605.1.15';
const _iphoneWkWebView =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const _iphoneFacebook =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/470.0.0.40.97]';
const _iphoneInstagram =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 350.0.0.17.104 (iPhone15,3; iOS 17_5; en_US)';
const _ipadOld =
    'Mozilla/5.0 (iPad; CPU OS 12_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1';
const _macSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const _macChrome =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
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

const _sha = 'aa11bb22cc33dd44ee55ff6677889900aa11bb22cc33dd44ee55ff6677889900';

/// What scripts/release/publish_release.py writes (Android files, Linux files + the web app, iOS / Windows / Mac
/// the web app).
final Map<String, Object?> _manifestJson = {
  'schema': 1,
  'updated_at': '2026-10-31T21:40:00Z',
  'platforms': {
    'android': {
      'version': '1.0.0',
      'build': 3,
      'min_build': 2,
      'released_at': '2026-10-31',
      'min_os': 'Android 7.0',
      'notes': {'ar': 'تحسينات', 'en': 'Improvements'},
      'primary': 'arm64-v8a',
      'files': [
        {'arch': 'arm64-v8a', 'kind': 'apk', 'url': 'https://alfheemacademy.com/releases/android/a64.apk', 'size': 48700000, 'sha256': _sha},
        {'arch': 'armeabi-v7a', 'kind': 'apk', 'url': 'android/a32.apk', 'size': 47000000, 'sha256': _sha.toUpperCase()},
        {'arch': 'universal', 'kind': 'apk', 'url': 'https://alfheemacademy.com/releases/android/all.apk', 'size': 99000000},
        {'arch': 'x86_64', 'kind': 'apk', 'url': 'http://alfheemacademy.com/releases/android/x.apk'},
        {'arch': 'bad', 'kind': 'apk', 'url': 'javascript:alert(1)'},
      ],
    },
    'ios': {'pwa': true},
    'windows': {'pwa': true},
    'macos': {'pwa': true},
    'linux': {
      'version': '1.0.0',
      'build': 3,
      'primary': 'pwa',
      'pwa': true,
      'files': [
        {'arch': 'x64', 'kind': 'deb', 'url': 'https://alfheemacademy.com/releases/linux/nb.deb', 'size': 30000000, 'sha256': _sha},
      ],
    },
    'tvos': {'pwa': true},
  },
};

final Uri _base = Uri.parse('https://alfheemacademy.com/releases/releases.json');
final ReleasesManifest _manifest = parseReleasesManifest(_manifestJson, base: _base);

GetAppEnv _web(GetAppOs os,
        {bool standalone = false,
        bool embedded = false,
        bool inApp = false,
        bool iosSafari = false,
        bool macSafari = false,
        bool installable = false,
        String? arch}) =>
    GetAppEnv(
      isWeb: true,
      os: os,
      standalone: standalone,
      embedded: embedded,
      inAppBrowser: inApp,
      iosSafari: iosSafari,
      macSafari: macSafari,
      pwaInstallable: installable,
      archHint: arch,
    );

void main() {
  // the real strings (Arabic and English), so the layouts are checked with the text users see
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

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

    test('desktops; Android is never Linux', () {
      expect(detectGetAppOs(_windowsEdge), GetAppOs.windows);
      expect(detectGetAppOs(_linuxFirefox), GetAppOs.linux);
      expect(detectGetAppOs(_ubuntuChrome), GetAppOs.linux);
      expect(_androidPhone.contains('Linux'), isTrue);
      expect(detectGetAppOs(_androidPhone), isNot(GetAppOs.linux));
    });

    test('unknown, TVs, consoles and ChromeOS get nothing', () {
      for (final ua in ['', 'curl/8.4.0', _chromeOs, _tizenTv, _xbox, _fireTv]) {
        expect(detectGetAppOs(ua), GetAppOs.other, reason: ua);
      }
    });
  });

  test('in-app browsers, wrappers, Safari', () {
    for (final ua in [_androidWebView, _iphoneWkWebView, _iphoneFacebook, _iphoneInstagram, _androidInstagram]) {
      expect(looksLikeInAppWebView(ua), isTrue, reason: ua);
    }
    for (final ua in [_androidPhone, _androidTablet, _iphoneSafari, _iphoneChrome, _ipadOld, _macSafari, _macFirefox,
      _windowsEdge, _linuxFirefox]) {
      expect(looksLikeInAppWebView(ua), isFalse, reason: ua);
    }
    expect(looksLikeAndroidWebView(_androidWebView), isTrue);
    expect(looksLikeAndroidWebView(_androidInstagram), isFalse, reason: 'a browser, not a wrapper');

    for (final ua in [_iphoneSafari, _iphoneSafari26, _ipadOld]) {
      expect(isIosSafari(ua), isTrue, reason: ua);
    }
    expect(isIosSafari(_macSafari, maxTouchPoints: 5), isTrue, reason: 'iPadOS asking for the desktop site');
    for (final ua in [_iphoneChrome, _iphoneEdge, _iphoneWkWebView, _iphoneFacebook, _iphoneInstagram, _macSafari,
      _androidPhone]) {
      expect(isIosSafari(ua), isFalse, reason: ua);
    }
    expect(isMacSafari(_macSafari), isTrue);
    for (final ua in [_macChrome, _macFirefox, _iphoneSafari, _windowsEdge]) {
      expect(isMacSafari(ua), isFalse, reason: ua);
    }
    expect(isMacSafari(_macSafari, maxTouchPoints: 5), isFalse, reason: 'an iPad, not a Mac');
  });

  test('archFromClientHints', () {
    expect(archFromClientHints(GetAppOs.android, 'arm', '64'), 'arm64-v8a');
    expect(archFromClientHints(GetAppOs.android, 'arm', '32'), isNull, reason: '32-bit Chrome on a 64-bit phone');
    expect(archFromClientHints(GetAppOs.android, '', ''), isNull);
    expect(archFromClientHints(GetAppOs.macos, 'arm', '64'), 'arm64');
    expect(archFromClientHints(GetAppOs.windows, 'x86', '64'), 'x64');
    expect(archFromClientHints(GetAppOs.windows, 'x86', '32'), isNull);
    expect(archFromClientHints(GetAppOs.ios, 'arm', '64'), isNull);
  });

  group('parseReleasesManifest', () {
    test('keeps https files (relative ones resolved), checks sha-256, drops junk', () {
      final a = _manifest['android']!;
      expect(a.version, '1.0.0');
      expect((a.build, a.minBuild, a.minOs), (3, 2, 'Android 7.0'));
      expect(a.files.map((f) => f.arch).toList(), ['arm64-v8a', 'armeabi-v7a', 'universal']);
      expect(a.files[1].url, 'https://alfheemacademy.com/releases/android/a32.apk');
      expect(a.files[1].sha256, _sha, reason: 'upper-case hex is normalised');
      expect(a.files[2].sha256, isNull);
      expect(a.files[0].fileName, 'a64.apk');
      expect(a.notes('ar'), 'تحسينات');
      expect(a.notes('en'), 'Improvements');
      expect(_manifest.updatedAt, DateTime.utc(2026, 10, 31, 21, 40));
    });

    test('a platform with nothing usable is not offered; broken input gives nothing', () {
      final m = parseReleasesManifest({
        'platforms': {
          'android': {'files': [{'url': 'http://x/a.apk'}]},
          'ios': {'pwa': 'yes'},
          'windows': 'nope',
        },
      });
      expect(m['android'], isNull);
      expect(m['ios'], isNull);
      expect(m['windows'], isNull);
      expect(m.isEmpty, isTrue);
      for (final j in [null, '<!doctype html>', [1, 2], {'platforms': []}, <String, Object?>{}]) {
        expect(parseReleasesManifest(j).isEmpty, isTrue, reason: '$j');
      }
    });

    test('primaryFile: the CPU first, then primary, universal, first', () {
      final a = _manifest['android']!;
      expect(a.primaryFile()!.arch, 'arm64-v8a');
      expect(a.primaryFile(archHint: 'armeabi-v7a')!.arch, 'armeabi-v7a');
      expect(a.primaryFile(archHint: 'mips')!.arch, 'arm64-v8a');
      const noPrimary = PlatformRelease(platform: 'x', files: [
        ReleaseFile(arch: 'a', kind: 'apk', url: 'https://x/a'),
        ReleaseFile(arch: 'universal', kind: 'apk', url: 'https://x/u'),
      ]);
      expect(noPrimary.primaryFile()!.arch, 'universal');
      expect(const PlatformRelease(platform: 'x').primaryFile(), isNull);
    });

    test('sizes', () {
      expect(formatReleaseSize(48700000), '48.7 MB');
      expect(formatReleaseSize(820000), '820 KB');
      expect(formatReleaseSize(1500000000), '1.5 GB');
      expect(formatReleaseSize(null), '');
      expect(formatReleaseSize(0), '');
    });
  });

  group('getAppOfferFor', () {
    GetAppOfferKind? kind(GetAppEnv env, [ReleasesManifest? m]) => getAppOfferFor(env, m ?? _manifest)?.kind;

    test('Android: the APK for most phones, the CPU when known', () {
      final o = getAppOfferFor(_web(GetAppOs.android), _manifest)!;
      expect(o.kind, GetAppOfferKind.download);
      expect(o.file!.arch, 'arm64-v8a');
      expect(getAppOfferFor(_web(GetAppOs.android, arch: 'universal'), _manifest)!.file!.arch, 'universal');
      expect(kind(_web(GetAppOs.android, inApp: true)), isNull, reason: 'an app browser cannot install an APK');
    });

    test('iPhone / iPad: Add to Home Screen in Safari, "open in Safari" anywhere else', () {
      expect(kind(_web(GetAppOs.ios, iosSafari: true)), GetAppOfferKind.installIos);
      expect(kind(_web(GetAppOs.ipados, iosSafari: true)), GetAppOfferKind.installIos);
      expect(kind(_web(GetAppOs.ios)), GetAppOfferKind.openInSafari, reason: 'Chrome / Edge on iOS');
      expect(kind(_web(GetAppOs.ios, inApp: true)), GetAppOfferKind.openInSafari, reason: 'Instagram, WhatsApp');
      final noIos = parseReleasesManifest({'platforms': {'android': (_manifestJson['platforms'] as Map)['android']}});
      expect(kind(_web(GetAppOs.ios, iosSafari: true), noIos), isNull, reason: 'not published: hidden');
    });

    test('computers: install the web app where the browser can, else the file, else nothing', () {
      expect(kind(_web(GetAppOs.windows, installable: true)), GetAppOfferKind.installWeb);
      expect(kind(_web(GetAppOs.windows)), isNull, reason: 'Firefox: no install, no file');
      expect(kind(_web(GetAppOs.macos, macSafari: true)), GetAppOfferKind.installWeb);
      expect(kind(_web(GetAppOs.macos)), isNull);
      expect(kind(_web(GetAppOs.linux, installable: true)), GetAppOfferKind.installWeb, reason: 'primary: pwa');
      final f = getAppOfferFor(_web(GetAppOs.linux), _manifest)!;
      expect((f.kind, f.file!.kind), (GetAppOfferKind.download, 'deb'), reason: 'Firefox on Linux: the package');
      expect(kind(_web(GetAppOs.windows, installable: true, inApp: true)), isNull);
    });

    test('never: native app, installed web app, wrapper, unknown device, empty manifest', () {
      expect(kind(GetAppEnv.native), isNull);
      for (final os in GetAppOs.values) {
        expect(kind(_web(os, standalone: true, iosSafari: true, installable: true)), isNull, reason: '$os');
        expect(kind(_web(os, embedded: true, iosSafari: true, installable: true)), isNull, reason: '$os');
        expect(kind(_web(os, iosSafari: true, installable: true), ReleasesManifest.empty), isNull, reason: '$os');
      }
      expect(kind(_web(GetAppOs.other, installable: true)), isNull);
    });
  });

  group('banner rules', () {
    final now = DateTime(2026, 10, 31, 12);
    final offer = getAppOfferFor(_web(GetAppOs.android), _manifest);

    test('dismissed: hidden for 14 days, then back; clock skew', () {
      bool show(DateTime? at) => shouldShowGetAppBanner(offer: offer, now: now, dismissedAt: at);
      expect(show(null), isTrue);
      expect(show(now), isFalse);
      expect(show(now.subtract(const Duration(days: 13, hours: 23))), isFalse);
      expect(show(now.subtract(const Duration(days: 14))), isTrue);
      expect(show(now.add(const Duration(hours: 2))), isFalse, reason: 'small clock skew still counts');
      expect(show(now.add(const Duration(days: 300))), isTrue, reason: 'a stamp far in the future is ignored');
      expect(shouldShowGetAppBanner(offer: null, now: now), isFalse);
    });

    test('settings row: any real tab with something published', () {
      expect(getAppEntryAvailable(_web(GetAppOs.windows), _manifest), isTrue, reason: 'lists the other platforms');
      expect(getAppEntryAvailable(_web(GetAppOs.other), _manifest), isTrue);
      expect(getAppEntryAvailable(_web(GetAppOs.android, standalone: true), _manifest), isFalse);
      expect(getAppEntryAvailable(_web(GetAppOs.android, embedded: true), _manifest), isFalse);
      expect(getAppEntryAvailable(GetAppEnv.native, _manifest), isFalse);
      expect(getAppEntryAvailable(_web(GetAppOs.android), ReleasesManifest.empty), isFalse);
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
  });

  group('native updates', () {
    test('updateNeedFor: force below min_build, suggest below build', () {
      final a = _manifest['android'];
      expect(updateNeedFor(installedBuild: 1, release: a), UpdateNeed.force);
      expect(updateNeedFor(installedBuild: 2, release: a), UpdateNeed.suggest);
      expect(updateNeedFor(installedBuild: 3, release: a), UpdateNeed.none);
      expect(updateNeedFor(installedBuild: 9, release: a), UpdateNeed.none);
      expect(updateNeedFor(installedBuild: 0, release: a), UpdateNeed.none, reason: 'unknown build never prompts');
      expect(updateNeedFor(installedBuild: 1, release: _manifest['ios']), UpdateNeed.none, reason: 'no file');
      expect(updateNeedFor(installedBuild: 1), UpdateNeed.none);
    });

    test('"Later" hides one build for 3 days', () {
      final now = DateTime(2026, 11, 1, 12);
      String at(int build, DateTime t) => '$build:${t.millisecondsSinceEpoch}';
      expect(updateSnoozed(null, 3, now), isFalse);
      expect(updateSnoozed(at(3, now.subtract(const Duration(days: 2))), 3, now), isTrue);
      expect(updateSnoozed(at(3, now.subtract(const Duration(days: 3))), 3, now), isFalse);
      expect(updateSnoozed(at(2, now), 3, now), isFalse, reason: 'a newer build asks again');
      expect(updateSnoozed('junk', 3, now), isFalse);
    });

    test('the manifest URL is the API host root', () {
      expect(releasesManifestUriFor('https://alfheemacademy.com/api').toString(),
          'https://alfheemacademy.com/releases/releases.json');
      expect(releasesManifestUriFor('http://10.0.2.2:18080/api').toString(),
          'http://10.0.2.2:18080/releases/releases.json');
    });
  });

  group('GetAppService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    GetAppService service(GetAppEnv env,
            {ReleasesManifest? m, DateTime? at, List<String>? pings, Set<String> off = const {}, String perm = 'default'}) =>
        GetAppService(
          env: () => env,
          loadManifest: () async => m ?? _manifest,
          clock: () => at ?? DateTime(2026, 10, 31, 12),
          ping: (p) => pings?.add(p),
          disabled: off.contains,
          notificationPermission: () => perm,
        );

    test('remembers a dismissal across instances; the row stays', () async {
      final a = service(_web(GetAppOs.android));
      await a.init();
      expect(a.bannerEligible, isTrue);
      await a.dismiss();
      expect(a.bannerEligible, isFalse);
      expect(a.entryAvailable, isTrue);
      final b = service(_web(GetAppOs.android), at: DateTime(2026, 11, 10));
      await b.init();
      expect(b.bannerEligible, isFalse, reason: '10 days later');
      final c = service(_web(GetAppOs.android), at: DateTime(2026, 11, 15));
      await c.init();
      expect(c.bannerEligible, isTrue, reason: '15 days later');
    });

    test('kill switches hide the banner and the row separately', () async {
      final a = service(_web(GetAppOs.android), off: {kGetAppBannerKey});
      await a.init();
      expect((a.bannerEligible, a.entryAvailable), (false, true));
      final b = service(_web(GetAppOs.android), off: {kGetAppEntryKey});
      await b.init();
      expect((b.bannerEligible, b.entryAvailable), (true, false));
    });

    test('analytics: one view per page load, platform + event only', () async {
      final pings = <String>[];
      final s = service(_web(GetAppOs.android), pings: pings);
      await s.init();
      s.trackView(GetAppOs.android);
      s.trackView(GetAppOs.android);
      s.track(GetAppOs.android, 'click');
      expect(pings, ['releases/ping/android/view', 'releases/ping/android/click']);
    });

    test('native / standalone / wrapper / broken manifest: nothing', () async {
      for (final s in [
        service(GetAppEnv.native),
        service(_web(GetAppOs.android, standalone: true)),
        service(_web(GetAppOs.android, embedded: true)),
        service(_web(GetAppOs.android), m: ReleasesManifest.empty),
      ]) {
        await s.init();
        expect((s.bannerEligible, s.entryAvailable, s.offer), (false, false, null));
      }
    });

    test('installed iPhone web app: the notifications strip until answered or closed', () async {
      final s = service(_web(GetAppOs.ios, standalone: true));
      await s.init();
      expect(s.pushPromptEligible, isTrue);
      await s.dismissPush();
      expect(s.pushPromptEligible, isFalse);
      for (final x in [
        service(_web(GetAppOs.ios, standalone: true), perm: 'granted'),
        service(_web(GetAppOs.ios, standalone: true), perm: 'unsupported'),
        service(_web(GetAppOs.ios, iosSafari: true)),
        service(_web(GetAppOs.android, standalone: true)),
        service(_web(GetAppOs.ios, standalone: true), off: {kGetAppBannerKey}),
      ]) {
        await x.init();
        expect(x.pushPromptEligible, isFalse);
      }
    });
  });

  group('layouts', () {
    setUp(() => AppConfig.lang = 'ar');

    final offers = [
      getAppOfferFor(_web(GetAppOs.android), _manifest)!,
      getAppOfferFor(_web(GetAppOs.ios, iosSafari: true), _manifest)!,
      getAppOfferFor(_web(GetAppOs.ipados, inApp: true), _manifest)!,
      getAppOfferFor(_web(GetAppOs.windows, installable: true), _manifest)!,
      getAppOfferFor(_web(GetAppOs.linux), _manifest)!,
    ];

    testWidgets('the strip: no overflow at 320 / 1400, ar / en, text x1.3, every kind', (tester) async {
      for (final o in offers) {
        await expectNoLayoutErrors(
          tester,
          () => Align(
            alignment: Alignment.topCenter,
            child: GetAppBannerView(
              icon: getAppIcon(o.os),
              title: getAppOfferTitle(o),
              meta: getAppOfferMeta(o),
              actionLabel: getAppOfferAction(o),
              onAction: () {},
              detailsLabel: translate('get_app_all_platforms'),
              onDetails: () {},
              onDismiss: () {},
            ),
          ),
        );
      }
    });

    testWidgets('the strip: one button, a 48 px close target, taps reach the callbacks', (tester) async {
      var action = 0, dismissed = 0, details = 0;
      tester.view.physicalSize = const Size(1000, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final o = offers.first;
      await tester.pumpWidget(layoutHost(Align(
        alignment: Alignment.topCenter,
        child: GetAppBannerView(
          icon: getAppIcon(o.os),
          title: getAppOfferTitle(o),
          meta: getAppOfferMeta(o),
          actionLabel: getAppOfferAction(o),
          onAction: () => action++,
          detailsLabel: translate('get_app_all_platforms'),
          onDetails: () => details++,
          onDismiss: () => dismissed++,
        ),
      )));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(translate('get_app_download')), findsOneWidget);
      expect(find.textContaining('48.7 MB'), findsOneWidget, reason: 'version and size in the strip');
      final close = find.bySemanticsLabel(translate('get_app_dismiss'));
      final size = tester.getSize(close);
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: '$size');
      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.text(translate('get_app_all_platforms')));
      await tester.tap(close);
      expect(action, 1);
      expect(details, 1);
      expect(dismissed, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('the sheet: every device, no overflow', (tester) async {
      final actions = GetAppActions(onDownload: (_, _) {}, onInstallWeb: () {}, onCopyLink: () {});
      for (final env in [
        _web(GetAppOs.android),
        _web(GetAppOs.ios, iosSafari: true),
        _web(GetAppOs.ios, inApp: true),
        _web(GetAppOs.macos, macSafari: true),
        _web(GetAppOs.linux),
        _web(GetAppOs.windows), // nothing for this browser: every platform listed
      ]) {
        await expectNoLayoutErrors(
          tester,
          () => GetAppSheetBody(env: env, manifest: _manifest, actions: actions),
        );
      }
    });

    testWidgets('the sheet: Android lists the other files and the checksum; downloads reach the callback',
        (tester) async {
      final got = <String>[];
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(layoutHost(GetAppSheetBody(
        env: _web(GetAppOs.android),
        manifest: _manifest,
        actions: GetAppActions(onDownload: (os, f) => got.add('${os.name}:${f.arch}'), onInstallWeb: () {}, onCopyLink: () {}),
      ), scale: 1));
      expect(find.text(_sha), findsOneWidget);
      expect(find.text(translate('get_app_android_fail')), findsOneWidget);
      expect(find.text(translate('get_app_platform_android')), findsNothing, reason: 'this device is not repeated');
      expect(find.text(translate('get_app_platform_linux')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, translate('get_app_download')));
      await tester.ensureVisible(find.widgetWithText(TextButton, translate('get_app_download')).last);
      await tester.tap(find.widgetWithText(TextButton, translate('get_app_download')).last);
      expect(got, ['android:arm64-v8a', 'linux:x64']);
    });

    testWidgets('the update dialog: no overflow, force has no "Later"', (tester) async {
      for (final force in [false, true]) {
        await expectNoLayoutErrors(
          tester,
          () => UpdateDialog(force: force, version: '1.2.0', size: '48.7 MB', notes: 'Faster lessons', onUpdate: () {}, onLater: () {}),
        );
      }
      await tester.pumpWidget(layoutHost(
          UpdateDialog(force: true, version: '1.2.0', onUpdate: () {}, onLater: () {}), scale: 1));
      expect(find.text(translate('get_app_update_later')), findsNothing);
      expect(find.text(translate('get_app_update_now')), findsOneWidget);
    });
  });
}
