// The Data Lab's shared building blocks in the Warm Editorial theme (D-610 – D-629): no overflow at 320 × 640 and
// 1400 × 900, Arabic and English, text × 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSpace;
import 'package:flutter_education_app/features/data_lab/data_lab_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _Blocks extends StatelessWidget {
  const _Blocks();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(children: [
      const DlHero(
        title: 'مختبر البيانات — الفيزياء الحديثة للصف الثالث الثانوي',
        subtitle: 'Grades, attendance and everything you track — in one sheet',
        icon: Icons.science_rounded,
        stats: [
          DlHeroStat(icon: Icons.groups_rounded, value: '12,480', label: 'students enrolled this term'),
          DlHeroStat(icon: Icons.trending_up_rounded, value: '76%', label: 'progress'),
          DlHeroStat(icon: Icons.event_available_rounded, value: '91%', label: 'attendance'),
        ],
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DlSectionTitle('الأعمدة التي يتابعها الجدول', subtitle: 'What the sheet tracks for every student'),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            const DlStatChip(icon: Icons.groups_rounded, value: '128', label: 'students'),
            DlActionPill(icon: Icons.upload_file_rounded, label: 'استيراد ملف Excel أو CSV من جهازك', onTap: () {}),
            DlChoiceChip(label: 'Numbers and progress bars', selected: true, onTap: () {}, icon: Icons.pin_rounded),
            DlChoiceChip(label: 'Progress', selected: false, onTap: () {}),
            DlTag('بانتظار الطالب لإكمال البيانات', c.warning, icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: AppSpace.md),
          const DlCard(
            child: Row(children: [
              DlAvatar(name: 'Laila'),
              SizedBox(width: AppSpace.sm),
              Expanded(child: DlBar(value: 72, marker: 60)),
              SizedBox(width: AppSpace.md),
              DlRing(value: 72, label: 'progress', size: 64),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          const DlCard(child: DlHistogram(buckets: [2, 6, 14, 22, 9])),
          const SizedBox(height: AppSpace.md),
          DlBanner(icon: Icons.lock_rounded, text: 'هذا العمود مقفل: لا يمكن لأحد تعديله حتى تفتحه.', color: c.warning),
          const SizedBox(height: AppSpace.md),
          DlField(controller: TextEditingController(), label: 'اسم العمود', hint: 'e.g. Midterm'),
          DlPrimaryButton(label: 'حفظ العمود وإظهاره للطلاب', icon: Icons.check_rounded, onPressed: () {}),
        ]),
      ),
    ]);
  }
}

void main() {
  testWidgets('data lab building blocks: no overflow', (t) async {
    await expectNoLayoutErrors(t, () => const _Blocks());
  });
}
