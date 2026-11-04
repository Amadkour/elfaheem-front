// Layout of the widgets redesigned by org-flow agent r1: no overflow at 320x640 / 1400x900, ar / en, text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_access_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('OrgRoleCard: long names, system, inherited, many holders', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        OrgRoleCard(
            role: const {
              'name_ar': 'مسؤول التسجيل والامتحانات والشؤون الأكاديمية بالكلية',
              'name_en': 'Registrar of examinations and academic affairs of the faculty',
              'description': 'Can see every student record, edit grades and print transcripts for the whole organization',
              'color': '#2F6FDE', 'holders': 1250, 'permissions': {'students': ['view']}, 'inherited': true,
            },
            onTap: () {}),
        OrgRoleCard(
            role: const {'name_ar': 'مدير', 'name_en': 'Admin', 'is_system': true, 'holders': 0, 'permissions': {}},
            onTap: () {}),
      ]),
    );
  });
}
