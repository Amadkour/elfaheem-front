// lib/features/admin/receipt_viewer.dart
// Premium receipt viewer shared by admin and teacher screens.
// Images open in an in-app zoomable viewer; PDFs use a safe browser/system handoff.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


Future<void> _launch(String url) async {
  var ok = false;
  try {
    ok = await launchUrl(
      Uri.parse(url),
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {}
  if (!ok)
    toast(t('تعذر فتح الإيصال', 'Could not open the receipt'), error: true);
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: context.colors.heroShade.withValues(alpha: 0.20),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const _BrandMark(icon: Icons.receipt_long_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('إيصال التحويل', 'Transfer receipt'),
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            t('مستند PDF', 'PDF document'),
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontSize: 12,
                              color: context.colors.textMedium,
                            ),
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
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 26,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.dangerTint,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: context.colors.danger.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: context.colors.cardBg,
                          borderRadius: BorderRadius.circular(24),
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
                      const SizedBox(height: 15),
                      Text(
                        t(
                          'الإيصال جاهز للعرض',
                          'Your receipt is ready to view',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t(
                          'سيتم فتح المستند في نافذة أو تطبيق خارجي.',
                          'The document will open in a browser or external PDF viewer.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: context.colors.textMedium,
                          height: 1.5,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
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
                            borderRadius: BorderRadius.circular(15),
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
                    const SizedBox(width: 10),
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
                            borderRadius: BorderRadius.circular(15),
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
      insetPadding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: size.height * 0.91,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
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
                padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 14, 14),
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
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('إيصال التحويل', 'Transfer receipt'),
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: context.colors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t(
                              'اضغط أو كبّر الصورة للتحقق من التفاصيل',
                              'Zoom in to inspect receipt details',
                            ),
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              color: context.colors.textMedium,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconAction(
                      icon: Icons.open_in_new_rounded,
                      tooltip: t('فتح في المتصفح', 'Open in browser'),
                      onTap: () => _launch(url),
                    ),
                    const SizedBox(width: 7),
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
                    boundaryMargin: const EdgeInsets.all(36),
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
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 380),
                            padding: const EdgeInsets.all(26),
                            decoration: BoxDecoration(
                              color: context.colors.onHero,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: context.colors.divider),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _BrandMark(
                                  icon: Icons.broken_image_outlined,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  t(
                                    'تعذر عرض الصورة هنا',
                                    'This image could not be displayed here',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    color: context.colors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  t(
                                    'يمكنك فتح الإيصال مباشرةً في المتصفح.',
                                    'You can open the receipt directly in your browser.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
                                    color: context.colors.textMedium,
                                    height: 1.5,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
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
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 13,
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
                padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                decoration: BoxDecoration(
                  color: context.colors.onHero,
                  border: Border(top: BorderSide(color: context.colors.divider)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 17, color: context.colors.textMedium),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        t(
                          'استخدم إصبعين أو عجلة الفأرة للتكبير',
                          'Pinch or use the mouse wheel to zoom',
                        ),
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: context.colors.textMedium,
                          fontSize: 12,
                        ),
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
    decoration: BoxDecoration(
      gradient: AppGradients.blend(context, color: context.colors.primary),
      borderRadius: BorderRadius.circular(compact ? 14 : 18),
      boxShadow: [
        BoxShadow(
          color: context.colors.primary.withValues(alpha: 0.20),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Icon(icon, color: context.colors.onHero, size: compact ? 21 : 26),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: context.colors.primary),
        ),
      ),
    ),
  );
}
