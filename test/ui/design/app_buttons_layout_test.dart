// AppButton / AppIconButton / AppButtonRow: every variant, size, busy and disabled state at 320 / 1400 wide, ar + en,
// textScaler 1.3, plus the behaviour (busy ignores taps, disabled has no handler, the row ends with the primary).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _long = 'حفظ التغييرات وإرسالها إلى جميع الطلاب المسجلين في المقرر الآن / Save changes and send to everyone';

Widget _all() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final size in AppButtonSize.values)
        for (final v in AppButtonVariant.values) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppButton(label: 'Save', onPressed: () {}, variant: v, size: size, icon: Icons.check_rounded),
            AppButton(label: 'Busy', onPressed: () {}, variant: v, size: size, busy: true),
            AppButton(label: 'Off', onPressed: null, variant: v, size: size, trailingIcon: Icons.arrow_forward),
          ]),
          AppButton(label: _long, onPressed: () {}, variant: v, size: size, expand: true, icon: Icons.send),
          const SizedBox(height: 8),
        ],
      AppButton.danger(label: 'Delete', onPressed: () {}, dangerOutline: true),
      Row(children: [
        AppIconButton(icon: Icons.edit, tooltip: 'Edit', onPressed: () {}),
        AppIconButton(icon: Icons.edit, tooltip: 'Edit', onPressed: () {}, variant: AppIconButtonVariant.tonal, badge: 150),
        AppIconButton(icon: Icons.edit, tooltip: 'Edit', onPressed: () {}, variant: AppIconButtonVariant.filled, badge: 3),
        const AppIconButton(icon: Icons.edit, tooltip: 'Edit', onPressed: null),
      ]),
      AppButtonRow(
        primary: AppButton.primary(label: _long, onPressed: () {}),
        secondary: [AppButton.secondary(label: 'Cancel', onPressed: () {}), AppButton.ghost(label: 'Later', onPressed: () {})],
      ),
    ]),
  );
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('every variant / size / state lays out', (tester) async {
    await expectNoLayoutErrors(tester, _all);
  });

  testWidgets('busy button ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(layoutHost(AppButton(label: 'Go', onPressed: () => taps++, busy: true)));
    await tester.tap(find.byType(AppButton));
    expect(taps, 0);
    await tester.pumpWidget(layoutHost(AppButton(label: 'Go', onPressed: () => taps++)));
    await tester.tap(find.byType(AppButton));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled button has no handler and sm has a 48 hit area', (tester) async {
    await tester.pumpWidget(layoutHost(const AppButton(label: 'Off', onPressed: null, size: AppButtonSize.sm)));
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
    expect(tester.getSize(find.byType(AppButton)).height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AppButtonRow puts the primary at the end in both directions', (tester) async {
    for (final lang in ['en', 'ar']) {
      AppConfig.lang = lang;
      await tester.pumpWidget(layoutHost(AppButtonRow(
        primary: AppButton.primary(label: 'Primary', onPressed: () {}),
        secondary: [AppButton.secondary(label: 'Second', onPressed: () {})],
      )));
      final p = tester.getCenter(find.text('Primary')).dx;
      final s = tester.getCenter(find.text('Second')).dx;
      if (lang == 'en') {
        expect(p, greaterThan(s));
      } else {
        expect(p, lessThan(s));
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
