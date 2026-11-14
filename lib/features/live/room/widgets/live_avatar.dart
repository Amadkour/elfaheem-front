// lib/features/live/room/widgets/live_avatar.dart
//
// The participant avatar of the live room: initials on a gradient derived from the name (one stable
// hue per person, see LivePalette.hueFor), or the person's photo when a URL is known, with a soft
// shadow and a "speaking" ring that pulses with the audio level. Plain values only — the LiveKit-bound
// widgets (participant.dart) and the recording placeholder (recording_placeholder.dart) build on it,
// and test/ui/live_participant_layout_test.dart pumps it without a Room.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// "Ahmed Hamdy Madkour" → "AH", "سارة محمود" → "سم", "" → "•". The first grapheme of the first two
/// words, upper-cased (a no-op for Arabic).
String liveInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '•';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

class LiveAvatar extends StatelessWidget {
  const LiveAvatar({
    super.key,
    required this.name,
    this.initials,
    this.imageUrl,
    this.size = 48,
    this.isSpeaking = false,
    this.audioLevel = 0,
    this.ring = true,
    this.shadow = true,
  });

  /// Drives the colour and the default initials.
  final String name;

  /// Overrides the initials computed from [name].
  final String? initials;

  /// The person's photo; the initials show while it loads and when it fails.
  final String? imageUrl;

  /// Diameter of the avatar itself. The speaking halo bleeds outside it without taking layout space.
  final double size;
  final bool isSpeaking;

  /// 0–1, LiveKit's `Participant.audioLevel`; scales the halo while speaking.
  final double audioLevel;

  /// Whether the speaking ring / halo is drawn at all (off for the tiny roster rows).
  final bool ring;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final text = initials ?? liveInitials(name);
    final url = imageUrl?.trim() ?? '';
    final color = LivePalette.avatarColor(name);
    final speaking = ring && isSpeaking;
    final ringWidth = math.max(1.5, size * 0.04);

    final face = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LivePalette.avatarGradient(name),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.38),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: url.isEmpty
              ? _Initials(text: text, size: size)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _Initials(text: text, size: size),
                ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (ring)
            _SpeakingHalo(active: speaking, level: audioLevel, size: size, color: LivePalette.success),
          // The ring itself: fades in/out in 250 ms, never jumps.
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: speaking ? LivePalette.success : LivePalette.success.withValues(alpha: 0),
                width: ringWidth,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(speaking ? ringWidth * 0.9 : 0),
              child: FittedBox(child: face),
            ),
          ),
        ],
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          text,
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: AppFonts.family,
            color: LivePalette.textHigh,
            fontSize: size * (text.length > 1 ? 0.38 : 0.44),
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: size * 0.01,
            shadows: [Shadow(color: LivePalette.shade(0.25), blurRadius: size * 0.08)],
          ),
        ),
      );
}

/// A soft pulse outside the avatar while the person speaks; its reach follows the audio level.
class _SpeakingHalo extends StatefulWidget {
  const _SpeakingHalo({required this.active, required this.level, required this.size, required this.color});
  final bool active;
  final double level;
  final double size;
  final Color color;

  @override
  State<_SpeakingHalo> createState() => _SpeakingHaloState();
}

class _SpeakingHaloState extends State<_SpeakingHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _SpeakingHalo old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level.clamp(0.0, 1.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.active ? 1 : 0,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          final reach = 1.12 + 0.22 * t + 0.16 * level;
          return OverflowBox(
            maxWidth: widget.size * 1.6,
            maxHeight: widget.size * 1.6,
            child: Container(
              width: widget.size * reach,
              height: widget.size * reach,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: (0.22 + 0.2 * level) * (1 - t)),
                border: Border.all(color: widget.color.withValues(alpha: 0.5 * (1 - t)), width: 1.5),
              ),
            ),
          );
        },
      ),
    );
  }
}
