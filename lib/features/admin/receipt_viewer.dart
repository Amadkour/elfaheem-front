// lib/features/admin/receipt_viewer.dart
//
// Opens a withdrawal receipt (image or PDF) from the short-lived signed link the server returns
// (GET .../receipt-url → {url, kind: 'image'|'pdf'}). Shared by the admin page and the teacher screen.
//
//   image → in-app viewer (pinch to zoom); falls back to "open in browser" if it cannot be drawn
//   pdf   → mobile/desktop: opens the system PDF viewer / browser at once
//           web: a dialog with an "Open" button — the click is a fresh user gesture, so the browser
//           does not block the new tab the way it does after an async network call.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> _launch(String url) async {
  var ok = false;
  try {
    ok = await launchUrl(
      Uri.parse(url),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {}
  if (!ok) toast(t('تعذر فتح الإيصال', 'Could not open the receipt'), error: true);
}

/// [link] is the map returned by `receiptLink(id)` in the providers.
Future<void> openReceipt(BuildContext context, Map<String, dynamic>? link) async {
  if (link == null) return; // the provider already toasted the error
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
    builder: (_) => isPdf ? _PdfDialog(url: url) : _ImageDialog(url: url),
  );
}

class _PdfDialog extends StatelessWidget {
  const _PdfDialog({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('إيصال التحويل', 'Transfer receipt'), style: const TextStyle(fontFamily: 'tajawal')),
        content: const Icon(Icons.picture_as_pdf_rounded, size: 56),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('إغلاق', 'Close'))),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(t('فتح PDF', 'Open PDF')),
            onPressed: () async {
              await _launch(url);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      );
}

class _ImageDialog extends StatelessWidget {
  const _ImageDialog({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 700, maxHeight: size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
                  // Web (CanvasKit) needs CORS headers on the storage host to DRAW a network image.
                  // If they are missing, offer the browser instead of a blank box.
                  errorBuilder: (_, __, ___) => SizedBox(
                    height: 200,
                    child: Center(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(t('فتح الإيصال في المتصفح', 'Open receipt in browser')),
                        onPressed: () => _launch(url),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(t('فتح', 'Open')),
                  onPressed: () => _launch(url),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t('إغلاق', 'Close'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
