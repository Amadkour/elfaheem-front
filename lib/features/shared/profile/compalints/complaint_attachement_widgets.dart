// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaint_attachment_widgets.dart
//
// Premium attachment presentation for the complaints feature.
// Drop-in replacement for the old `_NetworkThumb` / `_AttachmentGallery` /
// `_AttachmentThumb` widgets that were duplicated across
// `complaints_screen.dart` and `new_complaint_screen.dart`.
//
// Handles BOTH images and PDFs, for BOTH:
//   • already-uploaded server attachments  (ComplaintAttachment)
//   • not-yet-uploaded local attachments   (PendingAttachment)
//
// Needs `url_launcher` in pubspec.yaml (only new dependency):
//   url_launcher: ^6.3.0
// ─────────────────────────────────────────────────────────────────────────────

library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/app_config.dart';
import '../../../../utils/widget/app_network_image.dart';
import 'complaint_model.dart';
import 'complaint_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Shared helpers
// ═══════════════════════════════════════════════════════════════════════════

bool _isPdf({String? fileType, String? fileName, String? url}) {
  if ((fileType ?? '').toLowerCase().contains('pdf')) return true;
  final n = (fileName ?? '').toLowerCase();
  final u = (url ?? '').toLowerCase();
  return n.endsWith('.pdf') || u.endsWith('.pdf');
}

String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['KB', 'MB', 'GB'];
  double size = bytes / 1024;
  int i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size < 10 ? size.toStringAsFixed(1) : size.round()} ${units[i]}';
}

Future<void> _openExternally(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('could_not_open_file'.tr,
          style: const TextStyle(fontFamily: 'bahji')),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Server-side attachment tile (image OR pdf)
// ═══════════════════════════════════════════════════════════════════════════

class NetworkAttachmentTile extends StatelessWidget {
  const NetworkAttachmentTile({
    super.key,
    required this.attachment,
    this.size = 84,
  });

  final ComplaintAttachment attachment;
  final double size;

  bool get _pdf => _isPdf(
    fileType: attachment.fileType,
    fileName: attachment.fileName,
    url: attachment.fileUrl,
  );

  @override
  Widget build(BuildContext context) {
    final heroTag = 'attachment-${attachment.id}';
    return _AttachmentCard(
      size: size,
      onTap: () => _pdf
          ? _showPdfSheet(context, name: attachment.fileName, url: attachment.fileUrl, bytes: attachment.fileSize)
          : Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _ImageViewer(url: attachment.fileUrl, heroTag: heroTag),
      )),
      face: _pdf
          ? _PdfFace(name: attachment.fileName??'')
          : AppNetworkImage(
        heroTag: heroTag,
        url: attachment.fileUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The card's own onTap already pushes our custom _ImageViewer
        // (hero + pinch-zoom + share/open) — disable the widget's built-in
        // fullscreen so tapping doesn't trigger two navigations at once.
        enableFullscreen: false,
      ),
      isPdf: _pdf,
      sizeLabel: formatFileSize(attachment.fileSize),
    );
  }
}

/// Wrap-style gallery for a list of already-uploaded attachments.
class AttachmentGalleryGrid extends StatelessWidget {
  const AttachmentGalleryGrid({
    super.key,
    required this.attachments,
    this.tileSize = 84,
    this.showLabel = true,
  });

  final List<ComplaintAttachment> attachments;
  final double tileSize;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final c = context.themeConfig;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showLabel) ...[
        Row(children: [
          Icon(Icons.attach_file_rounded, size: 14, color: c.textLight),
          const SizedBox(width: 4),
          Text(
            '${'attachments_label'.tr} (${attachments.length})',
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textLight),
          ),
        ]),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: attachments
            .map((a) => NetworkAttachmentTile(attachment: a, size: tileSize))
            .toList(),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Local / pending attachment tile (before upload — with remove button)
// ═══════════════════════════════════════════════════════════════════════════

class PendingAttachmentTile extends StatelessWidget {
  const PendingAttachmentTile({
    super.key,
    required this.attachment,
    required this.onRemove,
    this.size = 84,
  });

  final PendingAttachment attachment;
  final VoidCallback onRemove;
  final double size;

  bool get _pdf => _isPdf(fileName: attachment.file.name, url: attachment.localPreviewUrl);

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      _AttachmentCard(
        size: size,
        onTap: () {},
        isPdf: _pdf,
        face: _pdf
            ? _PdfFace(name: attachment.file.name)
            : kIsWeb
            ? Image.network(attachment.localPreviewUrl, width: size, height: size, fit: BoxFit.cover)
            : Image.file(File(attachment.localPreviewUrl), width: size, height: size, fit: BoxFit.cover),
      ),
      Positioned(
        top: -6,
        right: -6,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared card chrome (shadow, rounded corners, badges)
// ═══════════════════════════════════════════════════════════════════════════

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.size,
    required this.face,
    required this.onTap,
    this.isPdf = false,
    this.sizeLabel,
  });

  final double size;
  final Widget face;
  final VoidCallback onTap;
  final bool isPdf;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            face,
            // subtle bottom gradient so badges stay legible on any image
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: size * 0.42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.45)],
                  ),
                ),
              ),
            ),
            if (!isPdf)
              Positioned(
                right: 6,
                bottom: 6,
                child: Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white.withValues(alpha: 0.9)),
              ),
            if (sizeLabel != null && sizeLabel!.isNotEmpty)
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(sizeLabel!,
                    style: const TextStyle(
                        fontFamily: 'bahji', fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The face shown inside the card for a PDF (no thumbnail rendering needed —
/// a clean branded icon face reads as "premium" and is instant, no network
/// round-trip to render a preview page).
class _PdfFace extends StatelessWidget {
  const _PdfFace({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final c = context.themeConfig;
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.primary.withValues(alpha: 0.16), c.primary.withValues(alpha: 0.06)],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'bahji', fontSize: 9, fontWeight: FontWeight.w600, color: c.primary),
          ),
        ]),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Fullscreen image viewer (pinch-zoom, hero, share/open actions)
// ═══════════════════════════════════════════════════════════════════════════

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.heroTag});
  final String url;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: AppNetworkImage(url: url, fit: BoxFit.contain, enableFullscreen: false),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _circleButton(Icons.close_rounded, () => Navigator.pop(context)),
              _circleButton(Icons.open_in_new_rounded, () => _openExternally(context, url)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black.withValues(alpha: 0.4),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white, size: 20)),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  PDF bottom sheet (name, size, open externally)
// ═══════════════════════════════════════════════════════════════════════════

void _showPdfSheet(BuildContext context, {required String? name, required String url, int? bytes}) {
  final c = context.themeConfig;
  showModalBottomSheet(
    context: context,
    backgroundColor: c.cardBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(2))),
          ),
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name ?? 'document.pdf',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'bahji', fontSize: 14, fontWeight: FontWeight.w700, color: c.textDark)),
                if (bytes != null && bytes > 0) ...[
                  const SizedBox(height: 2),
                  Text(formatFileSize(bytes),
                      style: TextStyle(fontFamily: 'bahji', fontSize: 12, color: c.textLight)),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openExternally(context, url);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text('open_document'.tr,
                  style: const TextStyle(fontFamily: 'bahji', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ),
  );
}