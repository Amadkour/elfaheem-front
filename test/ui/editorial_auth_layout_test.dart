// Warm Editorial (D-610 – D-629) restyle of the sign-in area: the pieces that changed shape — the passcode sheet,
// the guest promo block, the verification-way widgets, the Google and fingerprint buttons, the brand panel beside a
// form — at 320x640 and 1400x900, Arabic and English, textScaler 1.3 (layout harness: no overflow anywhere).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_education_app/features/auth/biometric.dart';
import 'package:flutter_education_app/features/auth/biometric_widgets.dart';
import 'package:flutter_education_app/features/auth/google_auth_flow.dart';
import 'package:flutter_education_app/features/auth/verify_way.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/features/shared/passcode/passcode_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'نص عربي طويل جداً لاختبار الالتفاف على الشاشات الصغيرة مع تكبير الخط إلى مئة وثلاثين بالمئة';
const _longEn = 'A very long English line that has to wrap on a 320 px phone with the text scaled to 130 percent';

void main() {
  testWidgets('passcode sheet', (t) async {
    await expectNoLayoutErrors(
      t,
      () => const SingleChildScrollView(
        child: PasscodeSheet(title: _longEn, hint: _longAr, wrongText: 'x', verify: _never, pinLength: 8),
      ),
    );
  });

  testWidgets('guest promo block', (t) async {
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: GuestPromoCard()));
  });

  testWidgets('verification-way widgets', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VerifyStepTracker(channels: ['email', 'phone'], pending: ['phone'], current: 'phone'),
            const SizedBox(height: 16),
            const Center(child: VerifyWayHero(way: VerifyWay.whatsapp)),
            const SizedBox(height: 16),
            const Center(child: VerifyDestinationChip(way: VerifyWay.email, text: 'someone.with.a.long.address@example.com')),
            const SizedBox(height: 16),
            VerifyWaySwitcher(
              ways: VerifyWay.values,
              selected: VerifyWay.telegram,
              verified: const {VerifyWay.email},
              onChanged: (_) {},
            ),
            const SizedBox(height: 16),
            VerifyWayButton(way: VerifyWay.telegram, label: _longEn, onPressed: () {}),
            const SizedBox(height: 16),
            const VerifyWayStatusPill(way: VerifyWay.sms, label: _longAr),
          ],
        ),
      ),
    );
  });

  testWidgets('Google and fingerprint buttons, the brand panel beside a form', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GoogleAuthButton(label: _longEn, onPressed: () {}),
            const SizedBox(height: 8),
            GoogleAuthButton(label: _longAr, loading: true, onPressed: () {}),
            const SizedBox(height: 8),
            Center(child: GoogleCircleButton(tooltip: 'Google', onPressed: () {})),
            const SizedBox(height: 8),
            BiometricSignInButton(kind: BiometricKind.face, onTap: () {}),
            const SizedBox(height: 8),
            const AuthMark(icon: Icons.verified_user_rounded),
          ],
        ),
      ),
    );
    await expectNoLayoutErrors(
      t,
      () => LayoutBuilder(
        builder: (context, box) => Row(children: [
          AuthSidebar(width: box.maxWidth >= 900 ? 420 : box.maxWidth * 0.6),
          const Expanded(child: SizedBox()),
        ]),
      ),
    );
  });
}

bool _never(String _) => false;
