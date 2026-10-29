// Fingerprint / Face ID sign-in UI (D-081): every piece lays out at 320x640 and 1400x900, Arabic and English, text
// 1.3 — the login card's quick sign-in (long names, no photo, busy), the offer sheet for each kind, the Security group
// with the switch (with and without the MFA row) — and the login screen shows the panel for a remembered account and
// the plain form otherwise (also when the kill switch is on).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/features/auth/biometric.dart';
import 'package:flutter_education_app/features/auth/biometric_widgets.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/mfa.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _rec = BiometricRecord(
  credentialId: 'c-1',
  seed: 's',
  userId: 7,
  name: 'Ahmed Hamdy Abdelrahman Mohamed Madkour El-Sayed',
  identifier: 'ahmed.hamdy.madkour.long.address@university.example.edu',
);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.disableList = []);
  tearDown(BiometricAuth.instance.debugReset);

  group('pieces', () {
    for (final busy in [false, true]) {
      testWidgets('quick sign-in (busy: $busy)', (t) async {
        await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BiometricQuickSignIn(
              name: _rec.name,
              initials: _rec.initials,
              identifier: _rec.identifier,
              kind: BiometricKind.fingerprint,
              busy: busy,
              onSignIn: () {},
              onForget: () {},
            ),
          ),
        );
      });
    }

    for (final kind in BiometricKind.values) {
      testWidgets('offer sheet ($kind)', (t) async {
        await expectNoLayoutErrors(t, () => BiometricOfferSheetBody(kind: kind, onEnable: () {}, onLater: () {}));
      });
    }

    testWidgets('security group: MFA + fingerprint switch, and the switch alone', (t) async {
      await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: Column(children: [
            MfaSecurityGroup(
              status: const MfaStatus(allowed: true, enabled: true),
              onTap: () {},
              biometric: const BiometricRowState(kind: BiometricKind.face, on: true),
              onBiometricChanged: (_) {},
            ),
            const MfaSecurityGroup(biometric: BiometricRowState(kind: BiometricKind.generic, on: false, busy: true)),
          ]),
        ),
      );
    });
  });

  group('login screen', () {
    late StorageService storage;
    late FakeApi api;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      storage = await StorageService.getInstance();
      api = FakeApi({
        'GET /api/v1/auth/policy': (_) => {'login_identifier': 'email', 'verification_method': 'email'},
      }, fallback: (_) => const <String, dynamic>{})
        ..install();
    });
    tearDownAll(() => api.uninstall());

    Widget app() => MultiProvider(providers: appProviders(storage: storage, api: ApiClient()), child: const LoginScreen());

    testWidgets('a remembered account: greeting, quick sign-in, the identifier field folded away; no overflow', (t) async {
      BiometricAuth.instance.debugSet(supported: true, record: _rec);
      await expectNoLayoutErrors(t, app, frames: 6);
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(app()));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(BiometricQuickSignIn), findsOneWidget);
      expect(find.text('Welcome back, Ahmed'), findsOneWidget);
      expect(find.text('Sign in with fingerprint'), findsOneWidget);
      expect(find.text(_rec.identifier!), findsOneWidget, reason: 'who signs in is shown; the field is not repeated');
      expect(find.byType(TextField), findsOneWidget, reason: 'only the password field');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('no key, or the kill switch: the plain form', (t) async {
      BiometricAuth.instance.debugSet(supported: true, clearRecord: true);
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(app()));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(BiometricQuickSignIn), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);

      AppConfig.disableList = [kBiometricFeatureKey];
      BiometricAuth.instance.debugSet(supported: true, record: _rec);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(layoutHost(app()));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(BiometricQuickSignIn), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
