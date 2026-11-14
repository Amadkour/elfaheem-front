import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/course_access.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_access_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

CourseAccess _a(String reason, {bool has = false, int? days}) => CourseAccess(
      hasAccess: has,
      reason: reason,
      expiresAt: DateTime.utc(2026, 11, 20),
      daysLeft: days,
      status: days != null ? 'expiring_soon' : null,
    );

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  tearDownAll(() => translation = {});

  testWidgets('banner: expiring and expired', (tester) async {
    for (final a in [_a('enrolled', has: true, days: 3), _a('expired')]) {
      await expectNoLayoutErrors(tester, () => Padding(padding: const EdgeInsets.all(16), child: CourseAccessBanner(access: a)));
    }
  });

  testWidgets('note: pending and support', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          CourseAccessNote(mode: EnrollBarMode.pending, access: _a('payment_pending')),
          const SizedBox(height: 8),
          CourseAccessNote(mode: EnrollBarMode.support, access: _a('cancelled')),
        ]),
      ),
    );
  });

  test('banner text only near the end', () {
    AppConfig.lang = 'en';
    expect(accessBannerText(_a('enrolled', has: true)), isNull);
    expect(accessBannerText(_a('enrolled', has: true, days: 3)), contains('in 3 days'));
    expect(accessBannerText(_a('expired')), isNotNull);
    expect(accessBannerText(null), isNull);
  });
}
