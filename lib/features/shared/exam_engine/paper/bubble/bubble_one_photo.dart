// One photo of any answer sheet (D-500): no corner marks, no four pictures. Plain-value widgets the layout harness pumps:
// the capture card, and the result drawn over the sheet with its one-tap fixes. Every verdict is the server's.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'bubble_flow.dart';
import 'bubble_sheet_view.dart';

/// The one step before the result: take or choose one picture of the sheet.
class BubbleCaptureCard extends StatelessWidget {
  const BubbleCaptureCard({super.key, required this.onFiles, this.onCamera, this.onWrittenTable, this.issues = const [], this.busy = false, this.error});

  final VoidCallback onFiles;
  final VoidCallback? onCamera;

  /// The sheet has a written answer table instead of bubbles.
  final VoidCallback? onWrittenTable;
  final List<BubbleIssue> issues;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: AppIconSize.sm, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textMedium))),
          ]),
        );
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.document_scanner_rounded, size: 56, color: c.primary),
        const SizedBox(height: AppSpace.sm),
        Text(t('صوّر ورقة الإجابة', 'Take one photo of the answer sheet'), style: AppType.headline(context), textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.xxs),
        Text(t('سنجد الأسئلة والاختيارات ورقم الطالب بأنفسنا، بدون علامات في الأركان.', "We'll find the questions, the choices and the student ID ourselves. No corner marks needed."),
            style: AppType.body(context).copyWith(color: c.textMedium), textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.md),
        tip(Icons.crop_free_rounded, t('الورقة كاملة داخل الصورة', 'The whole sheet inside the picture')),
        tip(Icons.light_mode_rounded, t('إضاءة جيدة وبدون ظل على الفقاعات', 'Good light, no shadow over the bubbles')),
        tip(Icons.check_circle_outline_rounded, t('فارغة أو مظلّلة، كلاهما يصلح', 'Empty or already filled, either works')),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          for (final i in issues) ...[AppBanner(icon: Icons.tips_and_updates_rounded, color: c.warning, text: i.text), const SizedBox(height: AppSpace.xs)],
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        ],
        const SizedBox(height: AppSpace.md),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpace.xs),
          Text(t('نبحث عن الأسئلة والاختيارات…', 'Finding the questions and choices…'), style: AppType.meta(context), textAlign: TextAlign.center),
        ] else ...[
          if (onCamera != null) ...[
            AppPrimaryButton(label: t('التقاط صورة', 'Take a photo'), icon: Icons.photo_camera_rounded, onPressed: onCamera),
            const SizedBox(height: AppSpace.xs),
            AppButton.secondary(label: t('اختيار صورة أو PDF', 'Choose a picture or PDF'), icon: Icons.upload_file_rounded, expand: true, onPressed: onFiles),
          ] else
            AppPrimaryButton(label: t('اختيار صورة أو PDF', 'Choose a picture or PDF'), icon: Icons.upload_file_rounded, onPressed: onFiles),
          if (onWrittenTable != null) ...[
            const SizedBox(height: AppSpace.xxs),
            AppButton.ghost(label: t('ورقتي جدول إجابات مكتوب', 'My sheet is a written answer table'), icon: Icons.table_rows_rounded, expand: true, onPressed: onWrittenTable),
          ],
        ],
      ]),
    );
  }
}

/// The result: the sheet with numbered questions, choices and the ID drawn on it, what to check, and one-tap fixes.
class BubbleResultPanel extends StatelessWidget {
  const BubbleResultPanel({
    super.key,
    required this.data,
    required this.image,
    required this.mode,
    required this.onMode,
    required this.onTapSheet,
    required this.onIdBox,
    required this.onRotate,
    required this.onDirection,
    required this.onOrder,
    required this.onBlockOptions,
    required this.onUndo,
    required this.onRetake,
    required this.onConfirm,
    required this.name,
    this.selectedBlock,
    this.busy = false,
    this.error,
    this.wide = false,
  });

  final BubbleImport data;
  final Uint8List? image;
  final BubbleTapMode? mode;
  final ValueChanged<BubbleTapMode?> onMode;
  final void Function(Offset fraction) onTapSheet;
  final void Function(Rect fractions) onIdBox;
  final VoidCallback onRotate, onDirection, onOrder, onUndo, onRetake, onConfirm;
  final void Function(BubbleBlock block, int options) onBlockOptions;
  final TextEditingController name;
  final BubbleBlock? selectedBlock;
  final bool busy, wide;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sheet = BubbleSheetView(
      image: image,
      aspect: data.imageW == 0 ? 1.414 : data.imageH / data.imageW,
      blocks: data.blocks,
      unsure: data.unsure,
      questions: data.marks,
      onTap: mode == null || mode == BubbleTapMode.dragId ? null : onTapSheet,
      onDragBox: mode == BubbleTapMode.dragId ? onIdBox : null,
    );
    final facts = AppCard(
      padding: AppSpace.card,
      child: Row(children: [
        Expanded(child: _Fact(value: '${data.questions}', label: t('سؤال', 'questions'))),
        Expanded(child: _Fact(value: data.optionsText, label: t('اختيارات', 'choices'))),
        Expanded(child: _Fact(value: data.idDigits > 0 ? '${data.idDigits}' : (data.idKind == 'none' ? '—' : data.idKind.toUpperCase()), label: t('رقم الطالب', 'student ID'))),
      ]),
    );
    final checks = <Widget>[
      for (final i in data.issues) ...[
        AppBanner(icon: Icons.photo_camera_back_rounded, color: c.danger, text: i.text),
        const SizedBox(height: AppSpace.xs),
      ],
      if (data.unsure.isEmpty && data.issues.isEmpty)
        AppBanner(icon: Icons.verified_rounded, color: c.success, text: t('وجدنا كل شيء بوضوح. راجع الورقة ثم احفظ.', 'Everything was clear. Check the sheet, then save.'))
      else
        for (final u in data.unsure.take(4)) ...[
          AppBanner(icon: Icons.visibility_rounded, color: c.warning, text: u.text),
          const SizedBox(height: AppSpace.xs),
        ],
    ];
    final picked = selectedBlock;
    final fixes = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('تصحيح بنقرة', 'Fix with one tap'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppButton.secondary(label: t('تدوير', 'Rotate'), icon: Icons.rotate_90_degrees_cw_rounded, onPressed: busy ? null : onRotate),
        AppButton.secondary(label: data.isRtl ? t('الترقيم: من اليمين', 'Numbering: right to left') : t('الترقيم: من اليسار', 'Numbering: left to right'), icon: Icons.swap_horiz_rounded, onPressed: busy ? null : onDirection),
        AppButton.secondary(label: data.isAcross ? t('الترتيب: صفًا بعد صف', 'Order: across the rows') : t('الترتيب: عمودًا بعد عمود', 'Order: down each column'), icon: Icons.format_list_numbered_rounded, onPressed: busy ? null : onOrder),
        if (data.rounds > 1) AppButton.ghost(label: t('تراجع', 'Undo'), icon: Icons.undo_rounded, onPressed: busy ? null : onUndo),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in BubbleTapMode.quickFixes) AppChoiceChip(label: m.label, selected: mode == m, onTap: () => onMode(mode == m ? null : m)),
      ]),
      if (mode != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(mode!.hint, style: AppType.meta(context).copyWith(color: c.primary)),
      ],
      if (mode == BubbleTapMode.fixOptions && picked != null) ...[
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(child: Text(t('عدد الاختيارات في هذه المجموعة', 'Choices in this group'), style: AppType.body(context))),
          IconButton(tooltip: t('أقل', 'Fewer'), icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: busy || picked.cols <= 2 ? null : () => onBlockOptions(picked, picked.cols - 1)),
          Text('${picked.cols}', style: AppType.section(context)),
          IconButton(tooltip: t('أكثر', 'More'), icon: const Icon(Icons.add_circle_outline_rounded), onPressed: busy || picked.cols >= 8 ? null : () => onBlockOptions(picked, picked.cols + 1)),
        ]),
      ],
    ]);
    final save = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: name, label: t('اسم الورقة', 'Sheet name')),
      const SizedBox(height: AppSpace.sm),
      if (error != null) ...[AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!), const SizedBox(height: AppSpace.sm)],
      AppPrimaryButton(key: const ValueKey('bubble.confirm'), label: t('الأسئلة صحيحة، احفظ الورقة', 'This is right, save the sheet'), icon: Icons.task_alt_rounded, busy: busy, onPressed: busy ? null : onConfirm),
      const SizedBox(height: AppSpace.xxs),
      AppButton.ghost(label: t('صورة أخرى', 'Use another picture'), icon: Icons.photo_camera_rounded, expand: true, onPressed: busy ? null : onRetake),
    ]);
    final legend = const BubbleSheetLegend();
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      facts,
      const SizedBox(height: AppSpace.sm),
      ...checks,
      const SizedBox(height: AppSpace.sm),
      fixes,
      const SizedBox(height: AppSpace.md),
      save,
    ]);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sheet, const SizedBox(height: AppSpace.xs), legend])),
        const SizedBox(width: AppSpace.lg),
        Expanded(flex: 2, child: side),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      facts,
      const SizedBox(height: AppSpace.sm),
      sheet,
      const SizedBox(height: AppSpace.xs),
      legend,
      const SizedBox(height: AppSpace.sm),
      ...checks,
      const SizedBox(height: AppSpace.sm),
      fixes,
      const SizedBox(height: AppSpace.md),
      save,
    ]);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Text(value, style: AppType.figureLarge(context).copyWith(color: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(label, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}
