// The super admin's shared building blocks in the Warm Editorial theme (D-610 – D-629): the page hero block, the
// paper cards, the selectable / switch rows, the save bar and the small admin_common widgets never overflow at
// 320 x 640 or 1400 x 900, in Arabic or English, at text x 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_premium_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _long = 'A long administrative title that keeps going so it has to wrap on a narrow phone screen';

void main() {
  testWidgets('premium hero, cards, rows and save bar', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => Scaffold(
          bottomNavigationBar: PremiumSaveBar(label: _long, onPressed: () {}),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PremiumHero(
                icon: Icons.tune_rounded,
                colors: AdminPalette.indigo,
                title: _long,
                subtitle: _long,
                footer: const Wrap(spacing: 8, runSpacing: 8, children: [
                  HeroPill(_long, icon: Icons.check_rounded),
                  HeroPill('12'),
                ]),
              ),
              PremiumCard(
                icon: Icons.payments_rounded,
                colors: AdminPalette.green,
                title: _long,
                hint: _long,
                children: [
                  PremiumSelectTile(
                    selected: true,
                    color: Colors.teal,
                    onTap: () {},
                    title: _long,
                    subtitle: _long,
                    leading: ServiceIcon(icon: Icons.star_rounded, colors: AdminPalette.orange, size: 40),
                    trailing: const Icon(Icons.check_circle_rounded),
                  ),
                  PremiumSwitchRow(title: _long, subtitle: _long, icon: Icons.bolt_rounded, value: true, onChanged: (_) {}),
                ],
              ),
            ],
          ),
        ),
      ),
      scaffold: false,
    );
  });

  testWidgets('section, status chip, key-value, empty and error states', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Section(
            title: _long,
            icon: Icons.receipt_long_rounded,
            trailing: const StatusChip('Waiting for the second review', Colors.orange),
            child: const Column(children: [KeyValue(_long, _long), KeyValue('id', '')]),
          ),
          const SizedBox(height: 320, child: EmptyState(_long)),
          SizedBox(height: 360, child: ErrorRetry(message: _long, onRetry: () {})),
        ],
      ),
    );
  });
}
