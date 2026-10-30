// lib/features/teacher/sessions/live/widgets/recording_placeholder.dart
//
// The frame the live room shows — and the recording captures — when there is nothing else to draw:
// no screen share, no camera. The recorder screenshots the whole live screen (room.dart's
// `_captureLiveScreenPng`, PNG at pixel ratio 1), so this widget IS the recorded placeholder; its
// output format is untouched here. Same visual language as the participant tiles: gradient backdrop
// tinted with the host's hue, the host's big avatar (photo or initials), the session title, the
// platform mark, a live dot, and the other participants as small avatars (up to what fits, then "+N").
//
// Plain values only: room.dart's `_PremiumWaitingPlaceholder` maps the LiveKit roster onto
// `PlaceholderParticipant`s; test/ui/live_participant_layout_test.dart pumps it directly.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'package:flutter_education_app/features/shared/live/live_room_words.dart';
import 'live_avatar.dart';
import 'live_palette.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class PlaceholderParticipant {
  const PlaceholderParticipant({
    required this.name,
    this.initials,
    this.imageUrl,
    this.isHost = false,
    this.isGuest = false,
    this.micOn = true,
    this.isSpeaking = false,
    this.audioLevel = 0,
  });

  final String name;
  final String? initials;
  final String? imageUrl;
  final bool isHost;
  final bool isGuest;
  final bool micOn;
  final bool isSpeaking;
  final double audioLevel;
}

class RecordingPlaceholderFrame extends StatelessWidget {
  const RecordingPlaceholderFrame({
    super.key,
    required this.host,
    this.others = const [],
    this.sessionTitle,
    this.platformName = '',
    this.showLogo = true,
    this.live = true,
    this.onTapHost,
    this.onTapOther,
    this.onTapOverflow,
  });

  final PlaceholderParticipant host;
  final List<PlaceholderParticipant> others;
  final String? sessionTitle;

  /// The platform's name next to its mark (AppIdentity.instance.name); hidden when empty.
  final String platformName;
  final bool showLogo;

  /// Shows the pulsing "live" dot in the top bar.
  final bool live;
  final VoidCallback? onTapHost;
  final void Function(int index)? onTapOther;
  final VoidCallback? onTapOverflow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
          final h = c.maxHeight.isFinite ? c.maxHeight : 300.0;
          final wide = w >= 720 && w > h * 1.15;
          final tint = LivePalette.avatarColor(host.name);
          final bg = LivePalette.bg;
          final title = (sessionTitle?.trim().isNotEmpty ?? false) ? sessionTitle!.trim() : liveTr('lr_live_session');

          final hero = _Hero(host: host, title: title, short: math.min(w, h), onTap: onTapHost);
          final roster = _Roster(others: others, onTap: onTapOther, onTapOverflow: onTapOverflow);

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(tint.withValues(alpha: 0.24), bg),
                  bg,
                  Color.alphaBlend(LivePalette.accent2.withValues(alpha: 0.18), bg),
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Two soft blobs: the host's hue top-start, the theme accent bottom-end.
                PositionedDirectional(
                  top: -h * 0.2,
                  start: -w * 0.15,
                  child: _Blob(color: tint, size: math.max(w, h) * 0.7),
                ),
                PositionedDirectional(
                  bottom: -h * 0.25,
                  end: -w * 0.2,
                  child: _Blob(color: LivePalette.accent, size: math.max(w, h) * 0.6),
                ),
                Column(
                  children: [
                    _TopBar(
                      platformName: platformName,
                      showLogo: showLogo,
                      live: live,
                      count: 1 + others.length,
                    ),
                    Expanded(
                      child: wide
                          ? Row(children: [
                              Expanded(flex: 5, child: hero),
                              Expanded(flex: 6, child: roster),
                            ])
                          : Column(children: [
                              Expanded(flex: others.isEmpty ? 1 : 5, child: hero),
                              if (others.isNotEmpty) Expanded(flex: 6, child: roster),
                            ]),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)]),
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.platformName, required this.showLogo, required this.live, required this.count});
  final String platformName;
  final bool showLogo;
  final bool live;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            if (showLogo)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 22,
                    height: 22,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Expanded(
              child: Text(
                platformName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: LivePalette.textMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (live) ...[
              _LiveChip(label: 'live'.tr),
              const SizedBox(width: 6),
            ],
            _CountChip(count: count),
          ],
        ),
      );
}

class _LiveChip extends StatefulWidget {
  const _LiveChip({required this.label});
  final String label;

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LivePalette.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.danger.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LivePalette.danger,
                  boxShadow: [
                    BoxShadow(color: LivePalette.danger.withValues(alpha: 0.3 + 0.5 * _c.value), blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: LivePalette.danger,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LivePalette.glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.glassBorder, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_alt_rounded, size: 12, color: LivePalette.textMid),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: LivePalette.textHigh,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

/// The host: big avatar, name, "host" badge + mic state, the session title.
class _Hero extends StatelessWidget {
  const _Hero({required this.host, required this.title, required this.short, this.onTap});
  final PlaceholderParticipant host;
  final String title;
  final double short;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = (short * 0.28).clamp(56.0, 168.0);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveAvatar(
          name: host.name,
          initials: host.initials,
          imageUrl: host.imageUrl,
          size: avatar,
          isSpeaking: host.isSpeaking,
          audioLevel: host.audioLevel,
        ),
        SizedBox(height: avatar * 0.14),
        Text(
          host.name.trim().isNotEmpty ? host.name.trim() : '•',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.family,
            color: LivePalette.textHigh,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Badge(
              label: host.isGuest
                  ? 'lr_guest'.tr
                  : host.isHost
                      ? 'lr_host'.tr
                      : 'lr_you'.tr,
              color: host.isGuest
                  ? LivePalette.warning
                  : host.isHost
                      ? LivePalette.accent
                      : LivePalette.textMid,
            ),
            const SizedBox(width: 6),
            _MicBadge(on: host.micOn),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.family,
            color: LivePalette.textMid,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
    // Never overflows its slot: clipped (no scrolling) if the slot is shorter than the stack of texts.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AppFonts.family,
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: 0.2,
          ),
        ),
      );
}

class _MicBadge extends StatelessWidget {
  const _MicBadge({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? LivePalette.glass : LivePalette.danger.withValues(alpha: 0.85),
          border: Border.all(color: on ? LivePalette.glassBorder : LivePalette.danger, width: 0.8),
        ),
        child: Icon(on ? Icons.mic_rounded : Icons.mic_off_rounded, size: 12, color: LivePalette.textHigh),
      );
}

/// The other participants as small avatar tiles, as many as fit the slot, then one "+N" tile.
class _Roster extends StatelessWidget {
  const _Roster({required this.others, this.onTap, this.onTapOverflow});
  final List<PlaceholderParticipant> others;
  final void Function(int index)? onTap;
  final VoidCallback? onTapOverflow;

  static const double _tileW = 84;
  static const double _tileH = 92;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final w = (c.maxWidth.isFinite ? c.maxWidth : 400.0) - 24;
          final h = (c.maxHeight.isFinite ? c.maxHeight : 300.0) - 16;
          final cols = math.max(1, ((w + _gap) / (_tileW + _gap)).floor());
          final rows = math.max(0, ((h + _gap) / (_tileH + _gap)).floor());
          final cap = cols * rows;
          final shown = others.length <= cap ? others : others.take(math.max(0, cap - 1)).toList();
          final overflow = others.length - shown.length;
          if (cap == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: _gap,
                  runSpacing: _gap,
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      _RosterTile(p: shown[i], onTap: onTap == null ? null : () => onTap!(i)),
                    if (overflow > 0) _OverflowTile(count: overflow, onTap: onTapOverflow),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.p, this.onTap});
  final PlaceholderParticipant p;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: _Roster._tileW,
          height: _Roster._tileH,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          decoration: BoxDecoration(
            color: LivePalette.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: p.isSpeaking ? LivePalette.success : LivePalette.glassBorder,
              width: p.isSpeaking ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 54,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    LiveAvatar(
                      name: p.name,
                      initials: p.initials,
                      imageUrl: p.imageUrl,
                      size: 44,
                      isSpeaking: p.isSpeaking,
                      audioLevel: p.audioLevel,
                    ),
                    if (!p.micOn)
                      Positioned(
                        bottom: -2,
                        right: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: LivePalette.danger,
                            border: Border.all(color: LivePalette.bg, width: 2),
                          ),
                          child: const Icon(Icons.mic_off_rounded, size: 9, color: LivePalette.textHigh),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  p.name.trim().isNotEmpty ? p.name.trim() : '•',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color: p.isGuest ? LivePalette.warning : LivePalette.textHigh,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _OverflowTile extends StatelessWidget {
  const _OverflowTile({required this.count, this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: _Roster._tileW,
          height: _Roster._tileH,
          decoration: BoxDecoration(
            color: LivePalette.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: LivePalette.glassBorder, width: 0.8),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '+$count',
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: LivePalette.textMid,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      );
}
