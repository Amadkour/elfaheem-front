/// utils/widget/recording_button.dart
///
/// A reusable button that appears on any session card when a recording is
/// available.  Tapping it opens the MP4 directly in the phone's default
/// video player (or browser) via url_launcher.
///
/// Usage (teacher sessions list):
///   RecordingButton(recordingUrl: session.recordingUrl)
///
/// Usage (student course-detail content tab):
///   RecordingButton(recordingUrl: session.recordingUrl)
///
/// The button is invisible / zero-height when recordingUrl is null.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/app_theme.dart';

class RecordingButton extends StatelessWidget {
  const RecordingButton({
    super.key,
    required this.recordingUrl,
    this.compact = false,
  });

  /// The MinIO / tunnel URL of the MP4.  Pass null to hide the widget.
  final String? recordingUrl;

  /// When true, renders a small icon-only pill (for use inside a session card).
  /// When false, renders a full-width button row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (recordingUrl == null || recordingUrl!.isEmpty) {
      return const SizedBox.shrink();
    }
    if (recordingUrl != null && recordingUrl!.contains('http://minio:9000')) {
      recordingUrl!.replaceFirst('http://minio:9000',
          'https://act-reviewer-beach-cuts.trycloudflare.com');
    }
    return compact
        ? _CompactPill(url: recordingUrl!)
        : _FullButton(url: recordingUrl!);
  }
}

// ── Full-width button ─────────────────────────────────────────────────────────

class _FullButton extends StatelessWidget {
  const _FullButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openUrl(context, url),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF1DB954).withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.play_circle_filled_rounded,
                color: Color(0xFF1DB954), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'شاهد التسجيل',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1DB954),
                ),
              ),
            ),
            const Icon(Icons.open_in_new_rounded,
                color: Color(0xFF1DB954), size: 16),
          ]),
        ),
      ),
    );
  }
}

// ── Compact pill (for inside session card rows) ───────────────────────────────

class _CompactPill extends StatelessWidget {
  const _CompactPill({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openUrl(context, url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF1DB954).withValues(alpha: 0.35)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_circle_outline_rounded,
              size: 13, color: Color(0xFF1DB954)),
          SizedBox(width: 5),
          Text(
            'التسجيل',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1DB954),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Launcher helper ───────────────────────────────────────────────────────────

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تعذّر فتح التسجيل',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }
}
