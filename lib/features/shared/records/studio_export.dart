// lib/features/shared/records/studio_export.dart — the Studio's Export panel (D-827), plain values so
// test/ui/records_studio_layout_test.dart pumps it on every size and language.
//
//   Settings   the name · Quality and size (Original / 1080p / 720p / 480p × Best / Balanced / Smaller, with the size
//              it comes to — the old Quality tool) · "Two files, split at the playhead" (the old Two files tool) ·
//              Keep / Replace the original (Records) or the draft note (a session material) · what comes out · Export
//   Job        the same panel follows the render: stages, %, time left, Stop; then Play · Download · Share ·
//              Publish (a material) · Continue editing. "Keep editing" closes the panel: the render goes on, the top
//              bar's Export button shows its percent and opens the panel again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart';
import 'records_studio_parts.dart';

/// The settings half of the Export panel.
class StudioExportSettings extends StatelessWidget {
  const StudioExportSettings({
    super.key,
    required this.item,
    required this.duration,
    required this.form,
    this.height,
    this.level = StudioQualityLevel.balanced,
    this.onQuality,
    this.twoFiles = false,
    this.halves,
    this.onTwoFiles,
    this.result = const [],
    this.problem,
    this.busy = false,
    this.draft = false,
    this.replace = false,
    this.onExport,
  });

  final RecordItem item;

  /// The edit's output length (the size estimate).
  final double duration;

  /// The name and Keep / Replace (StudioSaveArea.form).
  final Widget form;
  final int? height;
  final StudioQualityLevel level;

  /// Null: no quality choice (an audio file).
  final void Function(int? height, StudioQualityLevel level)? onQuality;
  final bool twoFiles;

  /// The two files' lengths at the playhead (null: the playhead is not inside the video).
  final (double, double)? halves;

  /// Null: the source offers no "Two files".
  final ValueChanged<bool>? onTwoFiles;

  /// The new length(s), for the summary.
  final List<double> result;
  final String? problem;
  final bool busy;
  final bool draft;
  final bool replace;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget caption(String s) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(s, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w700)),
        );
    final label = draft
        ? (twoFiles ? t('تصدير مسودتين', 'Export two drafts') : t('تصدير كمسودة', 'Export as a draft'))
        : twoFiles
            ? t('تصدير ملفين', 'Export two files')
            : replace
                ? t('تصدير واستبدال الأصل', 'Export and replace')
                : t('تصدير', 'Export');
    return Column(key: const ValueKey('studio.export.settings'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      form,
      if (onQuality != null) ...[
        const SizedBox(height: AppSpace.lg),
        caption(t('الجودة والحجم', 'Quality and size')),
        StudioToolPanel(
          tool: StudioTool.quality,
          item: item,
          duration: duration,
          height: height,
          level: level,
          enabled: !busy,
          onQuality: onQuality,
        ),
      ],
      if (onTwoFiles != null) ...[
        const SizedBox(height: AppSpace.md),
        AppSwitchTile(
          key: const ValueKey('studio.export.two'),
          title: t('ملفّان، يُقسمان عند المؤشر', 'Two files, split at the playhead'),
          subtitle: halves == null
              ? t('ضع المؤشر داخل الفيديو ليُقسم عنده', 'Put the playhead inside the video to split there')
              : t('${mmss(halves!.$1)} ثم ${mmss(halves!.$2)} — يحمل كلاهما كل تعديلاتك', '${mmss(halves!.$1)} then ${mmss(halves!.$2)} — both carry all your edits'),
          icon: Icons.call_split_rounded,
          value: twoFiles,
          onChanged: busy || (halves == null && !twoFiles) ? null : onTwoFiles,
        ),
      ],
      const SizedBox(height: AppSpace.md),
      StudioSummary(original: item.durationSeconds, result: result, problem: problem),
      const SizedBox(height: AppSpace.md),
      AppButton.primary(
        key: const ValueKey('studio.export.go'),
        label: label,
        icon: Icons.ios_share_rounded,
        busy: busy,
        expand: true,
        size: AppButtonSize.lg,
        onPressed: problem == null && !busy ? onExport : null,
      ),
      const SizedBox(height: AppSpace.xs),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.cloud_queue_rounded, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Text(
            t('يُصنع الملف على الخادم: يمكنك متابعة التعديل أو إغلاق الاستوديو، وسيصلك إشعار.',
                'The file is made on the server: keep editing or close the Studio, you will be notified.'),
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ),
      ]),
    ]);
  }
}

/// The job half: the job card, then "Keep editing" (closes the panel) and, once nothing runs, "Export again".
class StudioExportJob extends StatelessWidget {
  const StudioExportJob({super.key, required this.card, this.running = false, this.onKeepEditing, this.onExportAgain});

  final Widget card;
  final bool running;
  final VoidCallback? onKeepEditing;
  final VoidCallback? onExportAgain;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('studio.export.job'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          const SizedBox(height: AppSpace.md),
          Row(children: [
            if (onKeepEditing != null)
              Expanded(
                child: AppButton(
                  key: const ValueKey('studio.export.keep_editing'),
                  label: t('متابعة التعديل', 'Keep editing'),
                  icon: Icons.edit_rounded,
                  variant: running ? AppButtonVariant.primary : AppButtonVariant.secondary,
                  expand: true,
                  onPressed: onKeepEditing,
                ),
              ),
            if (onKeepEditing != null && onExportAgain != null && !running) const SizedBox(width: AppSpace.xs),
            if (onExportAgain != null && !running)
              Expanded(
                child: AppButton(
                  key: const ValueKey('studio.export.again'),
                  label: t('تصدير جديد', 'New export'),
                  icon: Icons.ios_share_rounded,
                  variant: AppButtonVariant.ghost,
                  expand: true,
                  onPressed: onExportAgain,
                ),
              ),
          ]),
        ],
      );
}
