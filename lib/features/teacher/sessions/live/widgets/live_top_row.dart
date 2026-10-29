// lib/features/teacher/sessions/live/widgets/live_top_row.dart
//
// The live room's top row (D-095): ONE line above the stage, never wrapping. Plain values only (no Room, no
// recorder), so test/ui/live_top_row_layout_test.dart pumps every state with the layout harness and
// test/visual/live_top_row_golden_test.dart renders it; room.dart's `_buildTopRow()` maps its state onto it.
//
//   start  ⓘ LIVE 12:34 — how long the room has been live (`live_started_at`); the chip is the room's info
//          button · the free-time countdown (+ Upgrade) · the weak-network pill · Room locked
//   end    the recording control · Full view · Minimize
//
// The recording control replaces the bottom bar's Pause / Resume, its REC chip and the meeting creator's pinned
// Record / Stop: a red "Record" button while this device may start one (a meeting's creator), a red dot + the
// recording time while recording (amber + pause glyph while paused); a tap opens Pause / Resume / Stop recording —
// exactly the actions the device had on the bar (a course's teacher: Pause / Resume; a meeting's creator: also
// Stop). Everyone sees "● REC" while the server records (no controls: the device does not record, D-090).
//
// Below [kLiveTopRowCompactWidth] the labels shrink to icons (the times stay) and the chips tighten; if it still
// does not fit (a crowded room on a 320 px phone), the start group scrolls sideways under a soft edge fade — the
// row never wraps and never overflows (320 px at text scale 1.3 included). Every tappable piece is a 48 px target;
// the visual chips are 40 px.
//
// Full view ([LiveTopRow.onFocus], shown while something fills the stage): room.dart hides this row, the bottom
// bar and the thumbnail strip; [LiveFocusExitButton] floats over the stage to bring them back (so do a tap on the
// stage, Esc and the back button).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/live/live_time_limit.dart' show LiveLimitTone, LiveTimeLimit;

import 'live_palette.dart';
import 'record/recorder_types.dart';

/// Below this width the row draws icons where it has room for labels on a wide screen.
const double kLiveTopRowCompactWidth = 600;

/// Whether the device's recorder controls (Pause / Resume) are offered. A teacher's follow the course's record
/// switch exactly as before; anyone else's (a meeting creator) only while THIS device is the one recording
/// ([recordsHere], room.dart `_recordsHere`). Pure, so the layout test covers every state.
bool showsRecorderControls({required bool isTeacher, required bool recordingEnabled, required bool recordsHere}) =>
    isTeacher ? recordingEnabled : recordsHere;

/// What the recording control shows.
enum LiveRecPhase {
  /// Nothing (nobody records, or this person may not know / do anything about it).
  none,

  /// The server records (LiveKit egress): "● REC" for everyone, no controls.
  server,

  /// This device may start a recording (a meeting's creator): the red "Record" button.
  offer,
  starting,
  recording,
  paused,
  uploading,
  saved,
  error,
}

/// The phase of the control. [state] = this device's recorder (null when it does not record); [pending] = a
/// recording was asked for and the recorder is not running yet; [offer] = Record may be pressed; [server] = the
/// room's server recording is on. The device's own recorder wins (it is the one with controls).
LiveRecPhase liveRecPhase({RecState? state, bool pending = false, bool offer = false, bool server = false}) {
  switch (state) {
    case RecState.starting:
      return LiveRecPhase.starting;
    case RecState.recording:
      return LiveRecPhase.recording;
    case RecState.paused:
      return LiveRecPhase.paused;
    case RecState.uploading:
      return LiveRecPhase.uploading;
    case RecState.done:
      return LiveRecPhase.saved;
    case RecState.error:
      return LiveRecPhase.error;
    case RecState.idle:
    case null:
      break;
  }
  if (pending) return LiveRecPhase.starting;
  if (offer) return LiveRecPhase.offer;
  if (server) return LiveRecPhase.server;
  return LiveRecPhase.none;
}

/// The recording control's values. A null callback hides that menu entry.
class LiveTopRecording {
  const LiveTopRecording({
    this.phase = LiveRecPhase.none,
    this.elapsed = Duration.zero,
    this.detail,
    this.busy = false,
    this.onRecord,
    this.onPause,
    this.onResume,
    this.onStop,
  });

  final LiveRecPhase phase;

  /// The recording's own time (paused time not counted).
  final Duration elapsed;

  /// The upload progress line in the menu ("Part 3 · 12.4 MB").
  final String? detail;

  /// A start / pause / resume is in flight: a spinner, no taps.
  final bool busy;
  final VoidCallback? onRecord;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;

  bool get hasMenu => onPause != null || onResume != null || onStop != null;

  /// The time is shown (recording / paused).
  bool get timed => phase == LiveRecPhase.recording || phase == LiveRecPhase.paused;
}

/// The free-time countdown (live_time_limit.dart's rules, computed by the room).
class LiveTopLimit {
  const LiveTopLimit({
    required this.remaining,
    this.tone = LiveLimitTone.calm,
    this.showUpgrade = false,
    this.busy = false,
    this.onUpgrade,
  });

  final Duration remaining;
  final LiveLimitTone tone;
  final bool showUpgrade;
  final bool busy;
  final VoidCallback? onUpgrade;
}

/// `mm:ss`, or `h:mm:ss` from an hour.
String liveClock(Duration d) => LiveTimeLimit.format(d);

class LiveTopRow extends StatelessWidget {
  const LiveTopRow({
    super.key,
    this.onInfo,
    this.liveFor,
    this.limit,
    this.netLowered = false,
    this.netRecovering = false,
    this.locked = false,
    this.onLocked,
    this.recording = const LiveTopRecording(),
    this.onFocus,
    this.onMinimize,
    this.pulse,
  });

  /// (i): the room's info sheet. Null hides it.
  final VoidCallback? onInfo;

  /// How long the room has been live; null hides the LIVE chip (not connected yet).
  final Duration? liveFor;

  /// The free-time countdown; null hides it.
  final LiveTopLimit? limit;

  /// D-090: the video was lowered for a weak connection ([netRecovering]: one step back up already).
  final bool netLowered;
  final bool netRecovering;

  /// The room is locked (hosts); [onLocked] opens the participants panel, where the switch is.
  final bool locked;
  final VoidCallback? onLocked;

  final LiveTopRecording recording;

  /// Full view; null hides the button (nothing fills the stage).
  final VoidCallback? onFocus;

  /// Shrinks the room to the floating box; null hides it (the room was pushed as a plain route).
  final VoidCallback? onMinimize;

  /// The REC blink (0.25–1); null draws a steady dot.
  final Animation<double>? pulse;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final compact = w < kLiveTopRowCompactWidth;
      // A phone with a status pill beside the clock: the LIVE chip drops its (i) glyph (it stays the info button).
      final crowded = compact && (limit != null || netLowered || locked);
      final start = <Widget>[
        if (liveFor != null)
          _LiveChip(liveFor: liveFor!, onInfo: onInfo, compact: compact, glyph: !crowded)
        else if (onInfo != null)
          _InfoButton(onTap: onInfo!),
        if (limit != null) _LimitChip(limit: limit!, compact: compact),
        if (netLowered) _NetChip(recovering: netRecovering, compact: compact),
        if (locked) _LockedChip(onTap: onLocked, compact: compact),
      ];
      final end = <Widget>[
        if (recording.phase != LiveRecPhase.none) _RecordControl(rec: recording, compact: compact, pulse: pulse),
        if (onFocus != null)
          _TopChip(
            key: const ValueKey('live_room.focus'),
            icon: Icons.fit_screen_rounded,
            label: compact ? null : t('عرض كامل', 'Full view'),
            dense: compact,
            tooltip: t('عرض المحتوى على الشاشة كلها (F)', 'Show the content on the whole screen (F)'),
            onTap: onFocus,
          ),
        if (onMinimize != null)
          _TopChip(
            key: const ValueKey('live_room.minimize'),
            icon: Icons.close_fullscreen_rounded,
            label: compact ? null : t('تصغير', 'Minimize'),
            dense: compact,
            tooltip: t('تصغير الغرفة ومتابعة استخدام التطبيق', 'Minimize the room and keep using the app'),
            onTap: onMinimize,
          ),
      ];
      final gap = compact ? 4.0 : 6.0;
      return SizedBox(
        key: const ValueKey('live_room.top_row'),
        height: height,
        child: Row(children: [
          Expanded(
            child: start.isEmpty
                ? const SizedBox.shrink()
                : _EdgeFadeScroll(child: Row(mainAxisSize: MainAxisSize.min, children: _gapped(start, gap))),
          ),
          if (end.isNotEmpty) ...[
            SizedBox(width: compact ? 6 : 8),
            ConstrainedBox(
              // The end group keeps its natural width; only an absurd text scale makes it scroll too.
              constraints: BoxConstraints(maxWidth: w * 0.72),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: _gapped(end, gap)),
              ),
            ),
          ],
        ]),
      );
    });
  }

  static List<Widget> _gapped(List<Widget> items, double gap) => [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(width: gap), items[i]],
      ];
}

/// The start group's sideways scroll: a soft fade on the edge where more chips wait (only while they do).
class _EdgeFadeScroll extends StatefulWidget {
  const _EdgeFadeScroll({required this.child});
  final Widget child;

  @override
  State<_EdgeFadeScroll> createState() => _EdgeFadeScrollState();
}

class _EdgeFadeScrollState extends State<_EdgeFadeScroll> {
  bool _before = false;
  bool _after = false;

  bool _onMetrics(ScrollMetrics m) {
    final before = m.pixels > 1;
    final after = m.pixels < m.maxScrollExtent - 1;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scroll = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: widget.child),
      ),
    );
    if (!_before && !_after) return scroll;
    final dir = Directionality.of(context);
    const solid = LivePalette.textHigh;
    final clear = LivePalette.textHigh.withValues(alpha: 0);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final f = rect.width <= 0 ? 0.0 : (28 / rect.width).clamp(0.0, 0.4);
        return LinearGradient(
          begin: AlignmentDirectional.centerStart.resolve(dir),
          end: AlignmentDirectional.centerEnd.resolve(dir),
          colors: [_before ? clear : solid, solid, solid, _after ? clear : solid],
          stops: [0, f, 1 - f, 1],
        ).createShader(rect);
      },
      child: scroll,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The floating "exit full view" button (room.dart draws it over the stage while in full view)
// ─────────────────────────────────────────────────────────────────────────────
class LiveFocusExitButton extends StatelessWidget {
  const LiveFocusExitButton({super.key, required this.onTap, this.recording = false, this.compact});

  final VoidCallback onTap;

  /// This device records: a small red dot, so the recording is never forgotten while the row is hidden.
  final bool recording;

  /// Icon only; null = below [kLiveTopRowCompactWidth] (phones).
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    final label = t('الخروج من العرض الكامل', 'Exit full view');
    return _TopChip(
      key: const ValueKey('live_room.focus_exit'),
      icon: Icons.fullscreen_exit_rounded,
      label: (compact ?? MediaQuery.sizeOf(context).width < kLiveTopRowCompactWidth) ? null : label,
      tooltip: '$label (Esc)',
      onTap: onTap,
      fill: LivePalette.shade(0.42),
      border: LivePalette.ink(0.22),
      ink: LivePalette.ink(0.92),
      lead: recording ? _Dot(color: LivePalette.danger, size: 8) : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _label(Color c, {double size = 13, FontWeight w = FontWeight.w800, double spacing = 0.1}) => TextStyle(
      fontFamily: AppFonts.family,
      fontSize: size,
      height: 1.15,
      fontWeight: w,
      color: c,
      letterSpacing: spacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

Color get _chipFill => LivePalette.surfaceHi.withValues(alpha: 0.88);

/// One chip of the row: a 40 px pill (a 40 px circle with an icon alone) inside a 48 px target, hover and press
/// washes, a tooltip, one semantics node.
class _TopChip extends StatefulWidget {
  const _TopChip({
    super.key,
    this.icon,
    this.lead,
    this.label,
    this.parts,
    this.trail,
    this.tooltip,
    this.onTap,
    this.onTapAnchor,
    this.fill,
    this.border,
    this.ink,
    this.glow,
    this.dense = false,
  });

  final IconData? icon;

  /// Drawn before [icon] / [label] (a dot, a spinner, a tag).
  final Widget? lead;
  final String? label;

  /// Replaces [label] (several texts).
  final List<Widget>? parts;
  final Widget? trail;
  final String? tooltip;
  final VoidCallback? onTap;

  /// A tap that needs the chip's own context (a menu anchored under it).
  final void Function(BuildContext anchor)? onTapAnchor;
  final Color? fill;
  final Color? border;
  final Color? ink;
  final Color? glow;

  /// Phones: tighter padding.
  final bool dense;

  @override
  State<_TopChip> createState() => _TopChipState();
}

class _TopChipState extends State<_TopChip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final ink = w.ink ?? LivePalette.textHigh;
    final tappable = w.onTap != null || w.onTapAnchor != null;
    final iconOnly = w.label == null && w.parts == null && w.lead == null && w.trail == null;
    final base = w.fill ?? _chipFill;
    final fill = !tappable
        ? base
        : _down
            ? Color.alphaBlend(LivePalette.ink(0.14), base)
            : _hover
                ? Color.alphaBlend(LivePalette.ink(0.08), base)
                : base;
    final inner = w.dense ? 6.0 : 7.0;
    final content = <Widget>[
      if (w.lead != null) w.lead!,
      if (w.lead != null && (w.icon != null || w.label != null || w.parts != null)) SizedBox(width: inner),
      if (w.icon != null) Icon(w.icon, size: 18, color: ink),
      if (w.icon != null && (w.label != null || w.parts != null)) SizedBox(width: inner),
      if (w.parts != null) ...w.parts!,
      // No Flexible: the row's groups scroll sideways, so a chip is laid out at its natural width.
      if (w.label != null) Text(w.label!, maxLines: 1, style: _label(ink)),
      if (w.trail != null) ...[const SizedBox(width: 4), w.trail!],
    ];
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 40,
      width: iconOnly ? 40 : null,
      padding: iconOnly ? null : EdgeInsets.symmetric(horizontal: w.dense ? 10 : 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: w.border ?? LivePalette.glassBorder),
        boxShadow: [
          BoxShadow(color: LivePalette.shade(0.28), blurRadius: 12, offset: const Offset(0, 3)),
          if (w.glow != null) BoxShadow(color: w.glow!, blurRadius: 14),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: content),
    );
    Widget target = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Center(widthFactor: 1, child: chip),
    );
    if (tappable) {
      target = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: w.onTapAnchor != null ? () => w.onTapAnchor!(context) : w.onTap,
          child: target,
        ),
      );
    }
    final label = w.tooltip ?? w.label ?? '';
    target = Semantics(button: tappable, label: label, excludeSemantics: true, child: target);
    if (w.tooltip == null) return target;
    return Tooltip(message: w.tooltip!, waitDuration: const Duration(milliseconds: 400), child: target);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 10, this.opacity = 1});
  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.35 + 0.65 * opacity),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55 * opacity), blurRadius: 8)],
        ),
      );
}

/// A dot that follows [pulse] (steady without one).
class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, this.pulse});
  final Color color;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final p = pulse;
    if (p == null) return _Dot(color: color);
    return AnimatedBuilder(animation: p, builder: (_, _) => _Dot(color: color, opacity: p.value));
  }
}

Widget _spinner(Color c) => SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: c));

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('live_room.info'),
        icon: Icons.info_outline_rounded,
        tooltip: t('عن الغرفة', 'About this room'),
        onTap: onTap,
      );
}

/// ⓘ LIVE 12:34 — how long the room has been live; with [onInfo], the chip is the room's info button too.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.liveFor, required this.compact, this.onInfo, this.glyph = true});
  final Duration liveFor;
  final bool compact;
  final VoidCallback? onInfo;

  /// The (i) glyph of the info button (dropped on a crowded phone row; the chip still opens the info sheet).
  final bool glyph;

  @override
  Widget build(BuildContext context) {
    final clock = liveClock(liveFor);
    final live = t('مباشر منذ $clock', 'Live for $clock');
    return _TopChip(
      key: ValueKey(onInfo != null ? 'live_room.info' : 'live_room.live_chip'),
      tooltip: onInfo != null ? '$live · ${t('عن الغرفة', 'About this room')}' : live,
      dense: compact,
      lead: onInfo != null && glyph ? Icon(Icons.info_outline_rounded, size: 17, color: LivePalette.ink(0.78)) : null,
      parts: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: LivePalette.danger, borderRadius: BorderRadius.circular(6)),
          child: Text(t('مباشر', 'LIVE'), style: _label(LivePalette.textHigh, size: 10.5, w: FontWeight.w900, spacing: 0.8)),
        ),
        SizedBox(width: compact ? 6 : 8),
        Text(clock, key: const ValueKey('live_room.live_time'), maxLines: 1, style: _label(LivePalette.textHigh)),
      ],
      onTap: onInfo,
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.limit, required this.compact});
  final LiveTopLimit limit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    final color = switch (l.tone) {
      LiveLimitTone.calm => LivePalette.textHigh,
      LiveLimitTone.warn => LivePalette.warning,
      LiveLimitTone.over => LivePalette.danger,
    };
    final over = l.tone == LiveLimitTone.over;
    final clock = liveClock(l.remaining);
    final text = over
        ? (compact ? '00:00' : t('انتهى الوقت المجاني', 'Free time is over'))
        : (compact ? clock : '${t('الوقت المجاني', 'Free time')} $clock');
    final upgradeInk = LivePalette.shade(0.85);
    final upgrade = l.showUpgrade && compact
        ? Container(
            key: const ValueKey('live_room.time_limit.upgrade'),
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: LivePalette.warning, shape: BoxShape.circle),
            child: Center(
              child: l.busy
                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: upgradeInk))
                  : Icon(Icons.bolt_rounded, size: 17, color: upgradeInk),
            ),
          )
        : l.showUpgrade
        ? Container(
            key: const ValueKey('live_room.time_limit.upgrade'),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: LivePalette.warning, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (l.busy)
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: LivePalette.shade(0.85)))
              else
                Icon(Icons.bolt_rounded, size: 15, color: LivePalette.shade(0.85)),
              const SizedBox(width: 4),
              Text(t('ترقية', 'Upgrade'), style: _label(LivePalette.shade(0.85), size: 12, w: FontWeight.w900)),
            ]),
          )
        : null;
    return _TopChip(
      key: const ValueKey('live_room.time_limit'),
      icon: compact && l.showUpgrade ? null : Icons.hourglass_bottom_rounded,
      dense: compact,
      ink: color,
      border: l.tone == LiveLimitTone.calm ? null : color.withValues(alpha: 0.6),
      tooltip: [
        over ? t('انتهى الوقت المجاني', 'Free time is over') : t('الوقت المجاني المتبقي $clock', 'Free time left $clock'),
        if (l.showUpgrade) t('ترقية', 'Upgrade'),
      ].join(' · '),
      parts: [Text(text, maxLines: 1, style: _label(color))],
      trail: upgrade == null ? null : Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: upgrade),
      onTap: l.showUpgrade && !l.busy ? l.onUpgrade : null,
    );
  }
}

class _NetChip extends StatelessWidget {
  const _NetChip({required this.recovering, required this.compact});
  final bool recovering;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    final tip = recovering
        ? t('الاتصال يتحسّن — تعود الجودة تدريجيًا', 'Connection improving — quality coming back')
        : t('الاتصال ضعيف — خُفِّضت جودة الفيديو', 'Poor connection — video quality lowered');
    return Semantics(
      liveRegion: true,
      child: _TopChip(
        key: const ValueKey('live_room.net_pill'),
        icon: recovering ? Icons.network_check_rounded : Icons.speed_rounded,
        label: compact ? null : (recovering ? t('يتحسّن', 'Improving') : t('اتصال ضعيف', 'Weak connection')),
        dense: compact,
        ink: color,
        border: color.withValues(alpha: 0.55),
        tooltip: tip,
      ),
    );
  }
}

class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.onTap, required this.compact});
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    return _TopChip(
      key: const ValueKey('live_room.locked'),
      icon: Icons.lock_rounded,
      label: compact ? null : t('مقفلة', 'Locked'),
      dense: compact,
      ink: color,
      border: color.withValues(alpha: 0.55),
      tooltip: t('الغرفة مقفلة', 'Room locked'),
      onTap: onTap,
    );
  }
}

enum _RecAction { pause, resume, stop }

/// The recording control (see the header).
class _RecordControl extends StatelessWidget {
  const _RecordControl({required this.rec, required this.compact, this.pulse});
  final LiveTopRecording rec;
  final bool compact;
  final Animation<double>? pulse;

  String get _stateText => switch (rec.phase) {
        LiveRecPhase.recording => t('يُسجَّل', 'Recording'),
        LiveRecPhase.paused => t('التسجيل متوقف مؤقتًا', 'Recording paused'),
        LiveRecPhase.starting => t('جارٍ بدء التسجيل…', 'Starting the recording…'),
        LiveRecPhase.uploading => t('جارٍ رفع التسجيل…', 'Uploading the recording…'),
        LiveRecPhase.saved => t('حُفظ التسجيل', 'Recording saved'),
        LiveRecPhase.error => t('تعذّر التسجيل', 'Recording failed'),
        LiveRecPhase.server => t('هذه الجلسة تُسجَّل', 'This session is being recorded'),
        LiveRecPhase.offer => t('تسجيل هذا الاجتماع', 'Record this meeting'),
        LiveRecPhase.none => '',
      };

  Future<void> _openMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rtl = Directionality.of(anchor) == TextDirection.rtl;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottom = topLeft.dy + box.size.height;
    final position = RelativeRect.fromLTRB(
      rtl ? topLeft.dx : topLeft.dx + box.size.width - 1,
      bottom,
      rtl ? overlay.size.width - topLeft.dx - 1 : overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
    final paused = rec.phase == LiveRecPhase.paused;
    final ink = paused ? LivePalette.warning : LivePalette.danger;
    PopupMenuItem<_RecAction> item(_RecAction a, String key, IconData icon, String label, VoidCallback? cb, Color c) =>
        PopupMenuItem<_RecAction>(
          key: ValueKey(key),
          value: a,
          enabled: cb != null,
          height: 48,
          child: Row(children: [
            Icon(icon, size: 20, color: cb == null ? LivePalette.textLow : c),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: _label(cb == null ? LivePalette.textLow : LivePalette.textHigh, size: 14, w: FontWeight.w700))),
          ]),
        );
    final picked = await showMenu<_RecAction>(
      context: anchor,
      color: LivePalette.surfaceHi,
      elevation: 20,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LivePalette.glassBorder)),
      position: position,
      items: [
        PopupMenuItem<_RecAction>(
          enabled: false,
          height: 52,
          child: Row(children: [
            paused ? Icon(Icons.pause_rounded, size: 18, color: ink) : _Dot(color: ink, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_stateText${rec.timed ? ' · ${liveClock(rec.elapsed)}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(LivePalette.textHigh, size: 13)),
                if (rec.detail != null)
                  Text(rec.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(LivePalette.textSoft, size: 11.5, w: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        const PopupMenuDivider(height: 1),
        if (rec.phase == LiveRecPhase.recording)
          item(_RecAction.pause, 'live_room.rec_menu.pause', Icons.pause_circle_outline_rounded, t('إيقاف مؤقت للتسجيل', 'Pause recording'),
              rec.onPause, LivePalette.warning),
        if (rec.phase == LiveRecPhase.paused)
          item(_RecAction.resume, 'live_room.rec_menu.resume', Icons.play_circle_outline_rounded, t('استئناف التسجيل', 'Resume recording'),
              rec.onResume, LivePalette.success),
        if (rec.onStop != null)
          item(_RecAction.stop, 'live_room.rec_menu.stop', Icons.stop_circle_rounded, t('إيقاف التسجيل', 'Stop recording'), rec.onStop,
              LivePalette.danger),
      ],
    );
    switch (picked) {
      case _RecAction.pause:
        rec.onPause?.call();
      case _RecAction.resume:
        rec.onResume?.call();
      case _RecAction.stop:
        rec.onStop?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rec;
    final danger = LivePalette.danger;
    final amber = LivePalette.warning;
    final chevron = Icon(Icons.expand_more_rounded, size: 18, color: LivePalette.ink(0.8));
    final clock = Text(liveClock(r.elapsed), maxLines: 1, style: _label(LivePalette.textHigh));
    switch (r.phase) {
      case LiveRecPhase.none:
        return const SizedBox.shrink();
      case LiveRecPhase.offer:
        return _TopChip(
          key: const ValueKey('live_room.record'),
          lead: r.busy ? _spinner(danger) : Icon(Icons.fiber_manual_record_rounded, size: 18, color: danger),
          label: t('تسجيل', 'Record'),
          dense: compact,
          tooltip: _stateText,
          border: danger.withValues(alpha: 0.6),
          onTap: r.busy ? null : r.onRecord,
        );
      case LiveRecPhase.server:
        return _TopChip(
          key: const ValueKey('live_room.rec_server'),
          lead: _PulseDot(color: danger, pulse: pulse),
          label: t('يُسجَّل', 'REC'),
          dense: compact,
          tooltip: _stateText,
          ink: danger,
          fill: Color.alphaBlend(danger.withValues(alpha: 0.16), _chipFill),
          border: danger.withValues(alpha: 0.5),
        );
      case LiveRecPhase.recording:
      case LiveRecPhase.paused:
        final paused = r.phase == LiveRecPhase.paused;
        final c = paused ? amber : danger;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          lead: r.busy ? _spinner(c) : (paused ? Icon(Icons.pause_rounded, size: 18, color: c) : _PulseDot(color: c, pulse: pulse)),
          parts: [
            if (!compact) ...[
              Text(paused ? t('متوقف', 'Paused') : t('يُسجَّل', 'REC'), maxLines: 1, style: _label(c, spacing: paused ? 0.2 : 0.8)),
              const SizedBox(width: 8),
            ],
            clock,
          ],
          // Phones: no chevron (every pixel counts; the tap still opens the menu).
          trail: r.hasMenu && !compact ? chevron : null,
          dense: compact,
          tooltip: '$_stateText · ${liveClock(r.elapsed)}',
          fill: Color.alphaBlend(c.withValues(alpha: 0.20), _chipFill),
          border: c.withValues(alpha: 0.65),
          glow: paused ? null : danger.withValues(alpha: 0.22),
          onTapAnchor: r.hasMenu && !r.busy ? _openMenu : null,
        );
      case LiveRecPhase.starting:
      case LiveRecPhase.uploading:
        final c = r.phase == LiveRecPhase.starting ? LivePalette.textHigh : amber;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          lead: _spinner(c),
          label: compact ? null : (r.phase == LiveRecPhase.starting ? t('جارٍ البدء…', 'Starting…') : t('جارٍ الرفع…', 'Uploading…')),
          tooltip: _stateText,
          ink: c,
          trail: r.hasMenu ? chevron : null,
          onTapAnchor: r.hasMenu ? _openMenu : null,
        );
      case LiveRecPhase.saved:
      case LiveRecPhase.error:
        final ok = r.phase == LiveRecPhase.saved;
        final c = ok ? LivePalette.success : danger;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          label: compact ? null : (ok ? t('حُفظ', 'Saved') : t('خطأ في التسجيل', 'Recording error')),
          tooltip: _stateText,
          ink: c,
          border: c.withValues(alpha: 0.55),
        );
    }
  }
}
