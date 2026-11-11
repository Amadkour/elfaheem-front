// lib/features/shared/exports/exports_center_page.dart
//
// The Export Studio's hub (D-130 / D-134) and the small pieces every export page shares.
//
//   ExportsCenterPage({admin})   tiles: Scheduled exports (export.schedules) · Shared links (export.share_links) ·
//                                Export log (admin.export_log, admins only); each tile carries its feature key
//   ExportFormatChip / ExportTintPill   the tinted format / status pills (text kept at WCAG AA over its tint)
//   ExportActionButton           an icon + text action with a 48 px target
//   ExportsLoadError             "needs a server update" banner, or a calm error with Try again
//   exportFormatLabel / exportFormatIcon / exportFormatColor / exportFormatOf / exportMimeOf / exportsListPadding
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart' show tx;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'export_links_page.dart';
import 'export_log_page.dart';
import 'export_schedules_page.dart';

const kExportSchedulesKey = 'export.schedules';
const kExportLinksKey = 'export.share_links';
const kExportLogKey = 'admin.export_log';

/// The widest the export pages' content grows on desktop.
const double kExportsMaxWidth = 880;

/// List padding that keeps the content at most [kExportsMaxWidth] wide, centred, with the page gutter.
EdgeInsets exportsListPadding(double width, {double top = AppSpace.sm, double bottom = AppSpace.xl}) {
  final g = AppSpace.gutter(width);
  final side = math.max(g, (width - kExportsMaxWidth) / 2);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

String exportFormatLabel(String format) => switch (format.toLowerCase()) {
      'xlsx' => 'Excel',
      'docx' => 'Word',
      'pdf' => 'PDF',
      'csv' => 'CSV',
      '' => tx('exs_format_file', 'File', 'ملف'),
      _ => format.toUpperCase(),
    };

IconData exportFormatIcon(String format) => switch (format.toLowerCase()) {
      'xlsx' => Icons.table_chart_rounded,
      'docx' => Icons.description_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'csv' => Icons.grid_on_rounded,
      _ => Icons.insert_drive_file_rounded,
    };

Color exportFormatColor(BuildContext context, String format) {
  final c = context.colors;
  return switch (format.toLowerCase()) {
    'xlsx' => c.success,
    'docx' => c.charcoal,
    'pdf' => c.danger,
    'csv' => c.accent2,
    _ => c.primary,
  };
}

/// The format of a file name, from its extension ('' when it has none).
String exportFormatOf(String? fileName) {
  final n = (fileName ?? '').trim();
  final dot = n.lastIndexOf('.');
  return dot < 0 || dot == n.length - 1 ? '' : n.substring(dot + 1).toLowerCase();
}

String exportMimeOf(String fileName) => switch (exportFormatOf(fileName)) {
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'pdf' => 'application/pdf',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };

/// A tinted pill: icon + label in [color], the label darkened / lightened until it reads (WCAG AA) on its tint.
class ExportTintPill extends StatelessWidget {
  const ExportTintPill(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color.withValues(alpha: 0.12);
    final ink = ensureContrast(color, [Color.alphaBlend(tint, c.cardBg)]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// The format of a file as a pill: "Excel" with the sheet icon, "PDF" with the PDF icon …
class ExportFormatChip extends StatelessWidget {
  const ExportFormatChip(this.format, {super.key});
  final String format;

  @override
  Widget build(BuildContext context) =>
      ExportTintPill(exportFormatLabel(format), color: exportFormatColor(context, format), icon: exportFormatIcon(format));
}

/// An action with an icon AND a text label, at least 48 × 48.
class ExportActionButton extends StatelessWidget {
  const ExportActionButton({super.key, required this.icon, required this.label, required this.onPressed, this.color, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = ensureContrast(color ?? c.primary, [c.cardBg]);
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: col,
        minimumSize: const Size(AppTouch.min, AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
      ),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: col))
          : Icon(icon, size: AppIconSize.md),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: col, fontWeight: FontWeight.w600)),
    );
  }
}

/// What a page shows when its load failed: [missing] → the "needs a server update" banner; otherwise the error and
/// a Try again button.
class ExportsLoadError extends StatelessWidget {
  const ExportsLoadError({super.key, required this.message, this.missing = false, this.onRetry});

  final String message;
  final bool missing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (missing) {
      return AppBanner(
        icon: Icons.system_update_rounded,
        color: c.warning,
        text: tx('exs_needs_update_long', 'This needs a server update. Ask your administrator to update the server.',
            'هذه الميزة تحتاج تحديث الخادم. اطلب من المسؤول تحديثه.'),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppEmpty(icon: Icons.cloud_off_rounded, title: tx('exs_load_failed', 'Could not load this page', 'تعذّر تحميل الصفحة'), message: message),
      if (onRetry != null)
        AppButton.secondary(label: tx('exs_retry', 'Try again', 'أعد المحاولة'), icon: Icons.refresh_rounded, onPressed: onRetry),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The hub
// ═════════════════════════════════════════════════════════════════════════════

String exportsCenterTitle() => tx('exs_center_title', 'Exports', 'التصدير');

class ExportsCenterPage extends StatelessWidget {
  const ExportsCenterPage({super.key, this.admin = false});

  /// Shows the Export log tile (platform / organization admins).
  final bool admin;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return BasePage(
      appBar: ScreenAppBar(title: exportsCenterTitle()),
      child: AppSettingsPage(groups: [
        AppSettingsGroup(
          title: tx('exs_center_mine', 'My exports', 'تصديراتي'),
          icon: Icons.file_download_rounded,
          children: [
            AppSettingsTile(
              icon: Icons.event_repeat_rounded,
              label: exportSchedulesTitle(),
              subtitle: tx('exs_center_schedules_sub', 'Files prepared for you on a timetable', 'ملفات تُجهَّز لك في مواعيد ثابتة'),
              featureKey: kExportSchedulesKey,
              onTap: () => _open(context, const ExportSchedulesPage()),
            ),
            AppSettingsTile(
              icon: Icons.link_rounded,
              label: exportLinksTitle(),
              subtitle: tx('exs_center_links_sub', 'Links to your files that expire on their own', 'روابط لملفاتك تنتهي صلاحيتها تلقائيًا'),
              featureKey: kExportLinksKey,
              onTap: () => _open(context, const ExportLinksPage()),
            ),
          ],
        ),
        if (admin)
          AppSettingsGroup(
            title: tx('exs_center_admin', 'Administration', 'الإدارة'),
            icon: Icons.admin_panel_settings_rounded,
            children: [
              AppSettingsTile(
                icon: Icons.manage_search_rounded,
                label: exportLogTitle(),
                subtitle: tx('exs_center_log_sub', 'Who exported what, and when', 'من صدّر ماذا ومتى'),
                featureKey: kExportLogKey,
                onTap: () => _open(context, const ExportLogPage()),
              ),
            ],
          ),
      ]),
    );
  }
}
