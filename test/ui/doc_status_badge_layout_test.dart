// The instructor profile's document badge shows the real review status (A18): the teacher viewing their own profile
// also gets pending and rejected documents, which must never read "Verified".
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/profile/course_instractor_profile.dart' show DocStatusBadge;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('approved → verified; pending, rejected and unknown are never verified', (t) async {
    Future<void> pump(String s) => t.pumpWidget(layoutHost(DocStatusBadge(status: s), scale: 1));
    await pump('approved');
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.text('verified'), findsOneWidget); // translation key (no translation file in tests)
    for (final s in ['pending', 'rejected', 'something_new']) {
      await pump(s);
      expect(find.byIcon(Icons.verified_rounded), findsNothing, reason: s);
    }
    await pump('rejected');
    expect(find.text('doc_rejected'), findsOneWidget);
    await pump('pending');
    expect(find.text('doc_pending'), findsOneWidget);
  });

  testWidgets('fits every screen, next to a date in a narrow column', (t) async {
    for (final s in ['approved', 'pending', 'rejected']) {
      await expectNoLayoutErrors(
          t,
          () => SizedBox(
              width: 120,
              child: Wrap(spacing: 8, runSpacing: 4, children: [DocStatusBadge(status: s), const Text('26/10/2026')])));
    }
  });
}
