// Exam Hub, Deliver: "What will be printed" (D-663), shown in the Print step before the button. Every document with its
// count (question paper, answer booklet, bubble sheet) and per what (named students, versions, blank sets), plus the
// booklet switch where a booklet can go with the paper. Plain values: the layout harness pumps it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'deliver_logic.dart';

class DeliverSummaryCard extends StatelessWidget {
  const DeliverSummaryCard({
    super.key,
    required this.summary,
    this.bookletOffered = false,
    this.booklet = false,
    this.onBooklet,
  });

  final DeliverPrintSummary summary;
  final bool bookletOffered, booklet;
  final ValueChanged<bool>? onBooklet;

  static IconData _icon(PrintDoc d) => switch (d) {
        PrintDoc.questionPaper => Icons.description_outlined,
        PrintDoc.booklet => Icons.menu_book_outlined,
        PrintDoc.bubbleSheet => Icons.grid_on_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('deliver.summary'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.primaryWash,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.primary.withValues(alpha: .18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('ما سيُطبع', 'What will be printed'), style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xs),
        for (final l in summary.lines)
          Padding(
            key: ValueKey('deliver.summary.${l.doc.name}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(children: [
              Icon(_icon(l.doc), size: AppIconSize.md, color: appInk(context, c.primary)),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(printDocLabel(l.doc), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                  if (l.separate)
                    Text(t('تُطبع من زر أوراق التظليل أدناه', 'Printed from Bubble answer sheets below'),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Text('×${l.count}', style: AppType.figure(context).copyWith(color: c.textDark)),
            ]),
          ),
        const SizedBox(height: AppSpace.xxs),
        Text(summary.per, style: AppType.meta(context).copyWith(height: 1.4)),
        if (summary.together)
          Text(t('كل ورقة أسئلة يليها دفترها في الملف نفسه.', 'Each question paper is followed by its booklet in the same file.'),
              style: AppType.meta(context).copyWith(color: c.textLight, height: 1.4)),
        if (bookletOffered) ...[
          const SizedBox(height: AppSpace.xs),
          AppSwitchTile(
            key: const ValueKey('deliver.booklet'),
            icon: Icons.menu_book_outlined,
            title: t('دفتر إجابة منفصل', 'A separate answer booklet'),
            subtitle: booklet
                ? t('يكتب الطلاب كل الإجابات في الدفتر، وورقة الأسئلة بلا مساحات للإجابة.', 'Students write every answer in the booklet; the question paper has no answer space.')
                : t('يجيب الطلاب على ورقة الأسئلة نفسها.', 'Students answer on the question paper itself.'),
            value: booklet,
            dense: true,
            onChanged: onBooklet,
          ),
        ],
      ]),
    );
  }
}
