// The re-auth sheet body (current password + optional two-step code) at 320 / 1400 wide, ar + en,
// textScaler 1.3 — with and without the MFA field.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('ReauthSheetBody with the two-step code field', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Scaffold(body: ReauthSheetBody(showMfa: true, onSubmit: (_) {})),
    );
  });

  testWidgets('ReauthSheetBody password only', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Scaffold(body: ReauthSheetBody(showMfa: false, onSubmit: (_) {})),
    );
  });
}
