// lib/features/admin/receipt_viewer.dart
// Premium receipt viewer shared by admin and teacher screens.
// Images open in an in-app zoomable viewer; PDFs use a safe browser/system handoff.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../../utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


Future<void> _launch(String url) async {
  await openExternalLink(url, failText: t('تعذر فتح الإيصال', 'Could not open the receipt'), webOnlyWindowName: '_blank');
}

/// [link] is the map returned by `receiptLink(id)` in the providers.
Future<void> openReceipt(
  BuildContext context,
  Map<String, dynamic>? link,
) async {
  if (link == null) return; // The provider already toasted the error.
  final url = asStr(link['url']);
  if (url.isEmpty) {
    toast(t('لا يوجد إيصال', 'No receipt available'), error: true);
    return;
  }

  final isPdf = asStr(link['kind']) == 'pdf';
  if (isPdf && !kIsWeb) {
    await _launch(url);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: context.colors.primary.withValues(alpha: 0.62),
    builder: (_) => isPdf ? _PdfDialog(url: url) : _ImageDialog(url: url),
  );
}

class _PdfDialog extends StatelessWidget {
  const _PdfDialog({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
   Color _ink = context.colors.primary;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            boxShadow: [
              BoxShadow(
                color: context.colors.heroShade.withValues(alpha: 0.20),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const _BrandMark(icon: Icons.receipt_long_rounded),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('إيصال التحويل', 'Transfer receipt'),
                            style: AppType.section(context).copyWith(color: _ink),
                          ),
                          const SizedBox(height: AppSpace.xxs),
                          Text(
                            t('مستند PDF', 'PDF document'),
                            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
                          ),
                        ],
                      ),
                    ),
                    _IconAction(
                      icon: Icons.close_rounded,
                      tooltip: t('إغلاق', 'Close'),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpace.lg,
                    horizontal: AppSpace.lg,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.dangerTint,
                    borderRadius: BorderRadius.circular(AppRadius.block),
                    border: Border.all(color: context.colors.danger.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: context.colors.cardBg,
                          borderRadius: BorderRadius.circular(AppRadius.block),
                          boxShadow: [
                            BoxShadow(
                              color: context.colors.danger.withValues(alpha: 0.10),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: context.colors.danger,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Text(
                        t(
                          'الإيصال جاهز للعرض',
                          'Your receipt is ready to view',
                        ),
                        textAlign: TextAlign.center,
                        style: AppType.section(context).copyWith(color: _ink),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        t(
                          'سيتم فتح المستند في نافذة أو تطبيق خارجي.',
                          'The document will open in a browser or external PDF viewer.',
                        ),
                        textAlign: TextAlign.center,
                        style: AppType.label(context).copyWith(color: context.colors.textMedium, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: BorderSide(color: context.colors.divider),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                        child: Text(
                          t('إغلاق', 'Close'),
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await _launch(url);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          t('فتح PDF', 'Open PDF'),
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          foregroundColor: context.colors.onHero,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageDialog extends StatelessWidget {
  const _ImageDialog({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpace.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: size.height * 0.91,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.block),
            boxShadow: [
              BoxShadow(
                color: context.colors.heroShade.withValues(alpha: 0.24),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
                decoration: BoxDecoration(
                  color: context.colors.onHero,
                  border: Border(bottom: BorderSide(color: context.colors.divider)),
                ),
                child: Row(
                  children: [
                    const _BrandMark(
                      icon: Icons.receipt_rounded,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('إيصال التحويل', 'Transfer receipt'),
                            style: AppType.section(context).copyWith(color: context.colors.primary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t(
                              'اضغط أو كبّر الصورة للتحقق من التفاصيل',
                              'Zoom in to inspect receipt details',
                            ),
                            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
                          ),
                        ],
                      ),
                    ),
                    _IconAction(
                      icon: Icons.open_in_new_rounded,
                      tooltip: t('فتح في المتصفح', 'Open in browser'),
                      onTap: () => _launch(url),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    _IconAction(
                      icon: Icons.close_rounded,
                      tooltip: t('إغلاق', 'Close'),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: context.colors.background,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(AppSpace.xl),
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const SizedBox(
                                height: 260,
                                child: Center(child: AppLoadingIndicator()),
                              ),
                        // Web CanvasKit needs CORS headers on the storage host to draw network images.
                        // If unavailable, offer a browser fallback rather than a blank viewer.
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 380),
                            padding: const EdgeInsets.all(AppSpace.lg),
                            decoration: BoxDecoration(
                              color: context.colors.onHero,
                              borderRadius: BorderRadius.circular(AppRadius.block),
                              border: Border.all(color: context.colors.divider),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _BrandMark(
                                  icon: Icons.broken_image_outlined,
                                ),
                                const SizedBox(height: AppSpace.md),
                                Text(
                                  t(
                                    'تعذر عرض الصورة هنا',
                                    'This image could not be displayed here',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: AppType.section(context).copyWith(color: context.colors.primary),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  t(
                                    'يمكنك فتح الإيصال مباشرةً في المتصفح.',
                                    'You can open the receipt directly in your browser.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: AppType.label(context).copyWith(color: context.colors.textMedium, height: 1.5),
                                ),
                                const SizedBox(height: AppSpace.md),
                                FilledButton.icon(
                                  onPressed: () => _launch(url),
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    t('فتح الإيصال', 'Open receipt'),
                                    style: TextStyle(
                                      fontFamily: AppFonts.family,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: context.colors.primary,
                                    foregroundColor: context.colors.onHero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.control),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpace.md,
                                      vertical: AppSpace.sm,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                decoration: BoxDecoration(
                  color: context.colors.onHero,
                  border: Border(top: BorderSide(color: context.colors.divider)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 17, color: context.colors.textMedium),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        t(
                          'استخدم إصبعين أو عجلة الفأرة للتكبير',
                          'Pinch or use the mouse wheel to zoom',
                        ),
                        style: AppType.meta(context).copyWith(color: context.colors.textMedium),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(foregroundColor: context.colors.primary),
                      child: Text(
                        t('إغلاق', 'Close'),
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.icon, this.compact = false});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 42 : 54,
    height: compact ? 42 : 54,
    // a faint emerald well with the icon in emerald ink (tone first, no glow)
    decoration: BoxDecoration(
      color: context.colors.blockEmerald,
      borderRadius: BorderRadius.circular(compact ? AppRadius.control : AppRadius.card),
    ),
    child: Icon(icon,
        color: context.colors.blockAccentInk(context.colors.primary, context.colors.blockEmerald),
        size: compact ? AppIconSize.md : AppIconSize.lg),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: context.colors.background,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: context.colors.primary),
        ),
      ),
    ),
  );
}
