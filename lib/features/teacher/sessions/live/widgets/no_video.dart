// lib/features/teacher/sessions/live/widgets/no_video.dart
//
// What a participant tile shows when the camera is off: the person's avatar (initials on their own
// gradient, or their photo) over a backdrop tinted with the same hue, a soft glow behind it and —
// when there is room — a small "camera off" chip. Scales from the 90 px thumbnail strip to a
// full-screen tile; plain values only (tested by test/ui/live_participant_layout_test.dart).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'live_avatar.dart';
import 'live_palette.dart';

class NoVideoWidget extends StatelessWidget {
  const NoVideoWidget({
    super.key,
    this.name = '',
    this.initials,
    this.imageUrl,
    this.isSpeaking = false,
    this.audioLevel = 0,
    this.showCaption = true,
  });

  final String name;
  final String? initials;
  final String? imageUrl;
  final bool isSpeaking;
  final double audioLevel;

  /// The "camera off" chip under the avatar (hidden on tiny tiles whatever this says).
  final bool showCaption;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
          final h = c.maxHeight.isFinite ? c.maxHeight : 240.0;
          final short = math.min(w, h);
          final avatar = (short * 0.42).clamp(24.0, 168.0);
          final roomy = showCaption && h >= 128 && w >= 128;
          final tint = LivePalette.avatarColor(name);
          final bg = LivePalette.bg;

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(tint.withValues(alpha: 0.2), bg),
                  bg,
                  Color.alphaBlend(LivePalette.accent2.withValues(alpha: 0.14), bg),
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // Glow behind the avatar, allowed to bleed past the tile (the tile clips it).
                Center(
                  child: OverflowBox(
                    maxWidth: avatar * 2.4,
                    maxHeight: avatar * 2.4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [tint.withValues(alpha: 0.3), tint.withValues(alpha: 0)],
                        ),
                      ),
                      child: SizedBox(width: avatar * 2.4, height: avatar * 2.4),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LiveAvatar(
                        name: name,
                        initials: initials,
                        imageUrl: imageUrl,
                        size: avatar,
                        isSpeaking: isSpeaking,
                        audioLevel: audioLevel,
                      ),
                      if (roomy) ...[
                        SizedBox(height: avatar * 0.18),
                        _CameraOffChip(label: 'lr_camera_off_msg'.tr),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _CameraOffChip extends StatelessWidget {
  const _CameraOffChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: LivePalette.glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 12, color: LivePalette.textLow),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  color: LivePalette.textMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
