// AppSwitchTile and the export sheet's pieces at 320 / 1400 wide, ar + en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('AppSwitchTile with a long label and subtitle', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppSwitchTile(
          title: 'السماح للطلاب بالانضمام إلى المنظمة عبر الكود أو الرابط دون موافقة المسؤول',
          subtitle: 'When enabled, students can join every department of the organization with a join code',
          icon: Icons.lock_open_rounded,
          value: true,
          onChanged: (_) {},
        ),
      ]),
    );
  });
}
