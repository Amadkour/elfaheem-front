// The listen-only bar (D-104): a slim strip pinned to the top of the app while a lecture plays as sound. Plain values
// only, so the layout harness and the visual renders can pump it; VodListenLayer feeds it from the session.
//
//   [art] Title of the lecture ……………………  [-10] (▶) [+10]  [⤢] [×]
//         ≋ Listening · 12:03 / 45:10 · 1.5×
//   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  progress line (drag or tap to move; the thumb shows while dragging)
//
// Under 520 px the art tile and the word "Listening" go (the equalizer says it), under 360 px the ±10 s buttons
// go (the line still seeks). The transport group and the line stay left-to-right in Arabic, like the full player.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_display.dart' show syncMotionLoop;
import '../../../../design/app_kit.dart' show appText;
import 'vod_player_parts.dart';

class VodListenBar extends StatefulWidget {
  const VodListenBar({
    super.key,
    required this.title,
    required this.position,
    required this.duration,
    this.buffered = 0,
    this.playing = false,
    this.busy = false,
    this.speed = 1.0,
    required this.onPlayPause,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onExpand,
    required this.onClose,
  });

  /// Height below the status bar.
  static const double height = 64;

  final String title;
  final Duration position, duration;

  /// Buffered part, 0…1.
  final double buffered;
  final bool playing;

  /// Opening a stream or buffering: the play button shows a spinner.
  final bool busy;
  final double speed;
  final VoidCallback onPlayPause, onExpand, onClose;
  final void Function(int seconds) onSeekBy;
  final void Function(double fraction) onSeekTo;

  @override
  State<VodListenBar> createState() => _VodListenBarState();
}

class _VodListenBarState extends State<VodListenBar> {
  double? _drag;

  void _dragTo(double dx, double width) {
    if (width <= 0) return;
    setState(() => _drag = (dx / width).clamp(0.0, 1.0));
  }

  void _dragEnd() {
    final f = _drag;
    if (f != null) widget.onSeekTo(f);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget;
    final finished = vodFinished(w.position, w.duration, playing: w.playing);
    final frac = vodFraction(w.position, w.duration, dragging: _drag);
    final shown = _drag == null ? w.position : Duration(milliseconds: (frac * w.duration.inMilliseconds).round());
    final speed = w.speed == 1.0 ? '' : '${_speedLabel(w.speed)}×';
    final time = w.duration > Duration.zero ? '${vodFmt(shown)} / ${vodFmt(w.duration)}' : vodFmt(shown);

    // A fixed-height strip: the text grows with the person's text size up to a point, then stays inside it.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: Material(
        color: c.cardBg,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider.withValues(alpha: 0.7)))),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: VodListenBar.height,
              child: LayoutBuilder(builder: (context, box) {
                // Phones: the time is what matters — the word "Listening" and the art tile come back from 520 px.
                final art = box.maxWidth >= 520;
                final skip = box.maxWidth >= 360;
                return Column(children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 0),
                          child: Row(children: [
                            if (art) ...[
                              _Art(playing: w.playing),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(w.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    _Equalizer(playing: w.playing, color: c.primary, size: 11),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text.rich(
                                        TextSpan(children: [
                                          if (art) ...[
                                            TextSpan(
                                                text: 'vod_listening'.tr,
                                                style: appText(11.5, w: FontWeight.w600, c: c.primary)),
                                            TextSpan(text: ' · ', style: appText(11.5, w: FontWeight.w400, c: c.textLight)),
                                          ],
                                          // "12:03 / 45:10" reads the same way in Arabic
                                          TextSpan(text: '$_lri$time$_pdi'),
                                          if (speed.isNotEmpty) ...[
                                            TextSpan(text: ' · ', style: appText(11.5, w: FontWeight.w400, c: c.textLight)),
                                            TextSpan(text: '$_lri$speed$_pdi', style: appText(11.5, w: FontWeight.w600, c: c.primary)),
                                          ],
                                        ]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: appText(11.5, w: FontWeight.w400, c: c.textMedium)
                                            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (skip)
                                  _BarButton(
                                      icon: Icons.replay_10_rounded, label: 'vod_back10'.tr, onTap: () => w.onSeekBy(-10)),
                                _PlayButton(
                                  playing: w.playing,
                                  finished: finished,
                                  busy: w.busy,
                                  onTap: w.onPlayPause,
                                ),
                                if (skip)
                                  _BarButton(
                                      icon: Icons.forward_10_rounded, label: 'vod_fwd10'.tr, onTap: () => w.onSeekBy(10)),
                              ]),
                            ),
                            _BarButton(icon: Icons.open_in_full_rounded, label: 'vod_expand'.tr, onTap: w.onExpand, size: 20),
                            _BarButton(icon: Icons.close_rounded, label: 'vod_close_listen'.tr, onTap: w.onClose),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  _ProgressLine(
                    fraction: frac,
                    buffered: w.buffered,
                    dragging: _drag != null,
                    label: '${'vod_position'.tr} $time',
                    onDrag: _dragTo,
                    onDragEnd: _dragEnd,
                    onStep: (f) => w.onSeekTo(f),
                  ),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }

  // Left-to-right isolate around the clock, so "12:03 / 45:10" is not reordered inside Arabic text.
  static final _lri = String.fromCharCode(0x2066);
  static final _pdi = String.fromCharCode(0x2069);

  static String _speedLabel(double s) => s == s.roundToDouble() ? s.toStringAsFixed(0) : '$s';
}

// ── Parts ───────────────────────────────────────────────────────────────────

class _Art extends StatelessWidget {
  const _Art({required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: c.primaryTint,
        border: Border.all(color: c.primary.withValues(alpha: 0.22)),
      ),
      child: Icon(Icons.headphones_rounded, size: 19, color: c.primary),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap, this.size = 22});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap, // screen readers and the web semantics tree activate the button through this
      child: SizedBox(
        width: 48,
        height: 48,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Center(child: Icon(icon, size: size, color: c.textMedium)),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.finished, required this.busy, required this.onTap});

  final bool playing, finished, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = finished ? 'vod_replay'.tr : (playing ? 'vod_pause'.tr : 'vod_play'.tr);
    final icon = finished ? Icons.replay_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap, // screen readers and the web semantics tree activate the button through this
      child: SizedBox(
        width: 48,
        height: 48,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero),
                    )
                  : Icon(icon, size: 22, color: c.onHero),
            ),
          ),
        ),
      ),
    );
  }
}

/// The thin line at the bottom edge of the bar: progress, buffered part, and a 12 px band to drag or tap.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.fraction,
    required this.buffered,
    required this.dragging,
    required this.label,
    required this.onDrag,
    required this.onDragEnd,
    required this.onStep,
  });

  final double fraction, buffered;
  final bool dragging;
  final String label;
  final void Function(double dx, double width) onDrag;
  final VoidCallback onDragEnd;
  final void Function(double fraction) onStep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = dragging ? 5.0 : 3.0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        slider: true,
        label: label,
        value: '${(fraction * 100).round()}%',
        increasedValue: '${math.min(100, (fraction * 100).round() + 5)}%',
        decreasedValue: '${math.max(0, (fraction * 100).round() - 5)}%',
        onIncrease: () => onStep(math.min(1, fraction + 0.05)),
        onDecrease: () => onStep(math.max(0, fraction - 0.05)),
        child: SizedBox(
          height: 12,
          child: LayoutBuilder(builder: (context, box) {
            final width = box.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => onDrag(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => onDrag(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => onDragEnd(),
              onHorizontalDragCancel: onDragEnd,
              onTapUp: (d) => onStep((d.localPosition.dx / math.max(1, width)).clamp(0.0, 1.0)),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: line,
                  child: ColoredBox(color: c.divider.withValues(alpha: 0.55)),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  height: line,
                  width: width * buffered.clamp(0.0, 1.0),
                  child: ColoredBox(color: c.primary.withValues(alpha: 0.22)),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  height: line,
                  width: width * fraction,
                  child: ColoredBox(color: c.primary),
                ),
                if (dragging)
                  Positioned(
                    left: (width * fraction - 7).clamp(0.0, math.max(0.0, width - 14)),
                    bottom: -4.5,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primary,
                        border: Border.all(color: c.cardBg, width: 2),
                      ),
                    ),
                  ),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

/// Three bars that dance while the sound plays (decorative: parked by Reduce motion, flat while paused).
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.playing, required this.color, this.size = 11});
  final bool playing;
  final Color color;
  final double size;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Equalizer old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      syncMotionLoop(context, _c, rest: 0.35);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value * 2 * math.pi;
            double h(double phase) =>
                widget.playing ? 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t + phase)).abs() : 0.3;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final p in const [0.0, 2.1, 4.2])
                  Container(
                    width: s / 4,
                    height: s * h(p),
                    decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(s / 8)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
