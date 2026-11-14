// lib/features/live/live_net_pill.dart
//
// What the room says while the weak-network governor holds the video down (D-090). Plain values, so
// test/ui/live_net_pill_layout_test.dart pumps them as they are and test/visual/live_media_golden_test.dart
// renders them.
//
//   LiveNetPill        "Poor connection — video quality lowered": a small amber pill in the room's top-end badge
//                      column while the tier is LOW / MEDIUM. Calm, never a dialog, never a toast storm.
//   LiveAudioOnlyCard  `weak_network: audio_first` below the threshold: "Audio only to keep you connected", why,
//                      and a "Show video" button (the person can always take the video back).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';

class LiveNetPill extends StatelessWidget {
  const LiveNetPill({super.key, this.recovering = false});

  /// One step back up already (MEDIUM): the text says it is coming back.
  final bool recovering;

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    final label = recovering
        ? t('الاتصال يتحسّن — تعود الجودة تدريجيًا', 'Connection improving — quality coming back')
        : t('الاتصال ضعيف — خُفِّضت جودة الفيديو', 'Poor connection — video quality lowered');
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          key: const ValueKey('live_room.net_pill'),
          constraints: const BoxConstraints(minHeight: 24),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: LivePalette.shade(0.58),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(recovering ? Icons.network_check_rounded : Icons.speed_rounded, size: 13, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class LiveAudioOnlyCard extends StatelessWidget {
  const LiveAudioOnlyCard({super.key, required this.onShowVideo, this.keepsScreen = false});

  final VoidCallback onShowVideo;

  /// A screen share is still on (at the lowest quality): the text says so.
  final bool keepsScreen;

  @override
  Widget build(BuildContext context) {
    final accent = LivePalette.accent;
    final title = t('صوت فقط للحفاظ على اتصالك', 'Audio only to keep you connected');
    final body = keepsScreen
        ? t('أوقفنا كاميرات الآخرين وأبقينا الشاشة المشتركة بجودة منخفضة. يعود الفيديو عندما يتحسّن الاتصال.',
            'Cameras are paused and the shared screen stays at low quality. Video comes back when the connection improves.')
        : t('أوقفنا الفيديو مؤقتًا لأن الاتصال ضعيف. يعود عندما يتحسّن الاتصال.',
            'Video is paused because the connection is weak. It comes back when the connection improves.');
    final button = _ShowVideoButton(onTap: onShowVideo);
    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Icon(Icons.headphones_rounded, size: 20, color: accent),
    );
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title,
          style: TextStyle(fontFamily: AppFonts.family, fontSize: 13.5, fontWeight: FontWeight.w800, color: LivePalette.textHigh, height: 1.3)),
      const SizedBox(height: 3),
      Text(body, style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: LivePalette.textMid, height: 1.4)),
    ]);
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          key: const ValueKey('live_room.audio_only'),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: LivePalette.shade(0.66),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: LivePalette.glassBorder),
            boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: LayoutBuilder(builder: (context, box) {
            // Narrow (a phone with large text): the button goes under the text, full width.
            if (box.maxWidth < 340) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: texts),
                ]),
                const SizedBox(height: 10),
                button,
              ]);
            }
            return Row(children: [
              icon,
              const SizedBox(width: 12),
              Expanded(child: texts),
              const SizedBox(width: 12),
              // Its own width, never more than ~40 % of the card (very large text: the label shortens).
              ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.42), child: button),
            ]);
          }),
        ),
      ),
    );
  }
}

class _ShowVideoButton extends StatelessWidget {
  const _ShowVideoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LivePalette.accent;
    final label = t('إظهار الفيديو', 'Show video');
    // The label sits on the accent: dark ink when the accent is light, white otherwise.
    final ink = accent.computeLuminance() > 0.45 ? LivePalette.shade(0.87) : LivePalette.textHigh;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('live_room.audio_only.show_video'),
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.videocam_rounded, size: 18, color: ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w800, color: ink),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
