// Public certificate verification (D-420): what a typed or scanned value means, the real server payloads, and the page
// with a guest: no token on the wire, no redirect, a malicious QR never leaves the device.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_logic.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345';

Map<String, dynamic> _fixture(String name) => (jsonDecode(File('test/fixtures/payloads/cert_verify_$name.json').readAsStringSync()) as Map).cast();

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  group('parseCertCode', () {
    test('our verification links give the token', () {
      for (final url in [
        'https://alfheemacademy.com/verify/$_token',
        'https://www.alfheemacademy.com/verify/$_token',
        'https://alfheemacademy.com/app/verify/$_token',
        'https://NEXTBRAIN.site/verify/$_token',
        'https://alfheemacademy.com:443/verify/$_token',
        'alfheemacademy.com/verify/$_token',
      ]) {
        final c = parseCertCode(url);
        expect(c.kind, CertCodeKind.token, reason: url);
        expect(c.value, _token, reason: url);
      }
    });

    test('anything else that is a link is foreign and carries no token', () {
      for (final (url, host) in [
        ('https://evil.example/verify/$_token', 'evil.example'),
        ('https://alfheemacademy.com.evil.example/verify/$_token', 'alfheemacademy.com.evil.example'),
        ('https://evilalfheemacademy.com/verify/$_token', 'evilalfheemacademy.com'),
        ('https://alfheemacademy.com@evil.example/verify/$_token', 'evil.example'),
        ('https://user:pw@alfheemacademy.com/verify/$_token', 'alfheemacademy.com'),
        ('http://alfheemacademy.com/verify/$_token', 'alfheemacademy.com'),
        ('https://alfheemacademy.com:8443/verify/$_token', 'alfheemacademy.com'),
        ('https://alfheemacademy.com/login', 'alfheemacademy.com'),
        ('https://alfheemacademy.com/verify/$_token/extra', 'alfheemacademy.com'),
        ('https://alfheemacademy.com/x/verify/$_token', 'alfheemacademy.com'),
        ('https://alfheemacademy.com/verify/short', 'alfheemacademy.com'),
        ('javascript:alert(1)', ''),
        ('intent://verify/$_token#Intent;scheme=https;end', 'verify'),
        ('tel:+201000000000', ''),
      ]) {
        final c = parseCertCode(url);
        expect(c.kind, CertCodeKind.foreign, reason: url);
        expect(c.value, host, reason: url);
      }
      expect(parseCertCode(r'https://evil.example\@alfheemacademy.com/verify/' + _token).kind, CertCodeKind.foreign);
    });

    test('numbers are normalised the way the server does; other text is malformed', () {
      expect(parseCertCode('NB-2026-ABC234').value, 'NB-2026-ABC234');
      expect(parseCertCode('  nb-2026-abc234 ').value, 'NB-2026-ABC234');
      final arabic = String.fromCharCodes('2026'.codeUnits.map((u) => 0x0660 + u - 0x30));
      expect(parseCertCode('NB-$arabic-ABC234').value, 'NB-2026-ABC234');
      final dash = String.fromCharCode(0x2013);
      expect(parseCertCode('NB${dash}2026${dash}ABC234').value, 'NB-2026-ABC234');
      expect(parseCertCode('${String.fromCharCode(0x200F)}NB-2026-ABC234').kind, CertCodeKind.number);
      expect(parseCertCode('EF-0012-003-00045').kind, CertCodeKind.number);
      for (final bad in ['', '   ', 'hello', 'NB-2026-ABC', 'NB-2026-ABCD0O', "' OR 1=1 --", 'x' * 700]) {
        expect(parseCertCode(bad).kind, CertCodeKind.malformed, reason: bad);
      }
    });

    test('routes: /verify is the public entry form, /verify/<token> stays the result', () {
      expect(isCertVerifyHomeRoute('/verify'), isTrue);
      expect(isCertVerifyHomeRoute('/verify/'), isTrue);
      expect(isCertVerifyHomeRoute('/verify/$_token'), isFalse);
      expect(certVerifyTokenFromRoute('/verify'), isNull);
      expect(certVerifyTokenFromRoute('/verify/$_token'), _token);
      expect(AppRoutes.match('/verify')!.id, 'link.verify_home');
      expect(AppRoutes.match('/verify/$_token')!.id, 'link.verify');
    });
  });

  group('real server payloads (tests/org_v2/cert_verify_public.py)', () {
    test('real, with an expiry', () {
      final r = VerifyResult.fromJson(_fixture('real'));
      expect(r.state, CertVerifyStatus.valid);
      expect(r.valid, isTrue);
      expect(r.expiresAt, isNotNull);
      expect(r.organization, 'جامعة النيل');
      expect(r.teacherName, 'د. منى حسن');
      expect(r.images.keys, containsAll(['ar', 'en']));
      expect(r.details.map((d) => d.key), containsAll(['hours', 'program', 'grade']));
      expect(r.byNumber, isFalse);
    });

    test('expired, no expiry, revoked, by number', () {
      final expired = VerifyResult.fromJson(_fixture('expired'));
      expect((expired.state, expired.valid, expired.expired), (CertVerifyStatus.expired, false, true));
      final never = VerifyResult.fromJson(_fixture('no_expiry'));
      expect((never.state, never.expiresAt), (CertVerifyStatus.valid, null));
      final revoked = VerifyResult.fromJson(_fixture('revoked'));
      expect((revoked.state, revoked.replaced), (CertVerifyStatus.revoked, true));
      final number = VerifyResult.fromJson(_fixture('number'));
      expect((number.byNumber, number.images.isEmpty, number.imageLangs.isEmpty), (true, true, true));
      expect(number.details.map((d) => d.key), isNot(contains('grade')));
      final masked = VerifyResult.fromJson(_fixture('number_masked'));
      expect((masked.nameMasked, masked.recipientName), (true, 'س*** ع*** م***'));
    });

    test('an older server: the state derives from the status, and there is no expiry', () {
      final ok = VerifyResult.fromJson({'valid': true, 'status': 'issued', 'serial': 'S', 'recipient_name': 'R'});
      expect((ok.state, ok.expiresAt), (CertVerifyStatus.valid, null));
      final gone = VerifyResult.fromJson({'valid': false, 'status': 'revoked'});
      expect(gone.state, CertVerifyStatus.revoked);
    });
  });

  group('the page, as a guest', () {
    final seen = <Map<String, dynamic>>[];
    late FakeApi api;

    FakeHandler answer(Object? body) => (o) {
          seen.add(o.headers);
          return body;
        };

    void install(Map<String, FakeHandler> routes) {
      mockRequestPlugins(accessToken: 'a-stored-token');
      seen.clear();
      api = FakeApi(routes, latency: Duration.zero)..install();
      addTearDown(api.uninstall);
    }

    setUp(() => AppConfig.lang = 'en');

    Future<void> pump(WidgetTester tester, CertVerifyPage page) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(home: page),
      ));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    void expectNoToken() {
      expect(seen, isNotEmpty);
      for (final h in seen) {
        expect(h.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      }
    }

    testWidgets('a typed number goes to the public route only, with no token', (tester) async {
      install({'GET /api/v1/public/certificates/lookup': answer(_fixture('number'))});
      await pump(tester, const CertVerifyPage(scanAvailable: false));
      expect(find.byKey(const ValueKey('cv.scan')), findsNothing, reason: 'no camera path: typing');
      await tester.enterText(find.byType(TextField), ' nb-2026-abcdef ');
      await tester.tap(find.byKey(const ValueKey('cv.verify')));
      await settle(tester);
      expect(api.calls.map((c) => c.path), ['/api/v1/public/certificates/lookup']);
      expect(api.calls.single.query['number'], 'NB-2026-ABCDEF');
      expectNoToken();
      expect(find.text('Real certificate'), findsOneWidget);
    });

    testWidgets('an unknown number is Fake, and a 404 never redirects', (tester) async {
      install({'GET /api/v1/public/certificates/lookup': answer(FakeResponse(404, _fixture('fake')))});
      await pump(tester, const CertVerifyPage(scanAvailable: false));
      await tester.enterText(find.byType(TextField), 'NB-2026-AAAAAA');
      await tester.tap(find.byKey(const ValueKey('cv.verify')));
      await settle(tester);
      expectNoToken();
      expect(find.text('Fake certificate'), findsOneWidget);
      expect(find.byKey(const ValueKey('cv.another')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('cv.another')));
      await tester.tap(find.byKey(const ValueKey('cv.another')));
      await tester.pump();
      expect(find.byKey(const ValueKey('cv.number')), findsOneWidget);
    });

    testWidgets('a scanned verify URL is looked up by its token', (tester) async {
      install({'GET /api/v1/public/certificates/verify/*': answer(_fixture('no_expiry'))});
      await pump(tester, CertVerifyPage(scanAvailable: true, scan: (_) async => 'https://alfheemacademy.com/verify/$_token'));
      await tester.tap(find.byKey(const ValueKey('cv.scan')));
      await settle(tester);
      expect(api.calls.single.path, '/api/v1/public/certificates/verify/$_token');
      expectNoToken();
      expect(find.text('Does not expire'), findsOneWidget);
    });

    testWidgets('a malicious scanned URL makes no call and is shown as a host, not a link', (tester) async {
      install(const {});
      await pump(tester, CertVerifyPage(scanAvailable: true, scan: (_) async => 'https://evil.example/verify/$_token'));
      await tester.tap(find.byKey(const ValueKey('cv.scan')));
      await settle(tester);
      expect(api.calls, isEmpty);
      expect(find.text('Not an Alfaheem code'), findsOneWidget);
      expect(find.textContaining('evil.example'), findsOneWidget);
    });

    testWidgets('a closed scanner changes nothing; typed junk stays on the form with a message', (tester) async {
      install(const {});
      await pump(tester, CertVerifyPage(scanAvailable: true, scan: (_) async => null));
      await tester.tap(find.byKey(const ValueKey('cv.scan')));
      await settle(tester);
      expect(find.byKey(const ValueKey('cv.number')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byKey(const ValueKey('cv.verify')));
      await tester.pump();
      expect(find.byKey(const ValueKey('cv.error')), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('a 429 shows the coded message', (tester) async {
      install({'GET /api/v1/public/certificates/verify/*': answer(FakeResponse(429, _fixture('rate_limited')))});
      await pump(tester, const CertVerifyPage(token: _token));
      await settle(tester);
      expect(find.textContaining('Too many checks'), findsOneWidget);
    });
  });
}
