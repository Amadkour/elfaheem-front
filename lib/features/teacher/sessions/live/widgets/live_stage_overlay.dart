// lib/features/teacher/sessions/live/widgets/live_stage_overlay.dart
//
// D-313: a meeting's shared content (the whiteboard, a shared screen) fills the whole room, edge to edge, and the
// room's controls float OVER it instead of taking room from it: the top row slides down from the top edge, the
// control bar (with the board's tool dock for whoever draws) up from the bottom, both on a translucent scrim; the
// participants' camera boxes stay over the page as before. One small toggle, always on screen at the top centre
// (a 48 px target), hides all of them and brings them back (AppMotion: at once under Reduce motion). While hidden it
// still says whether the meeting is recorded (a red dot / the amber pause glyph), so hiding the top row never hides
// the recording. The choice is remembered for the meeting in this app session ([LiveOverlayMemory]).
//
// No auto-hide: the controls stay until the toggle (or a tap on content nobody draws on) hides them — the owner asked
// for a button, and controls that vanish by themselves fight it and hide the recording state at the wrong moment.
//
// Course sessions keep their layout (full view, D-108, is still theirs). Plain values (the bars come in as widgets):
// test/ui/live_stage_overlay_layout_test.dart pumps it with the layout harness; the rules are unit-tested in
// test/org/live_stage_overlay_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'live_palette.dart';

/// The overlay layout is on: a meeting (never a course session) whose stage shows the whiteboard or a shared screen,
/// and the room is not parked (minimized with its video off).
bool liveStageOverlayOn({required bool isMeeting, required bool board, required bool screen, bool parked = false}) =>
    isMeeting && (board || screen) && !parked;

/// The controls' shown / hidden choice per meeting, for this app session (a minimize, a rejoin keeps it). Shown by
/// default.
class LiveOverlayMemory {
  LiveOverlayMemory._();

  static final Map<String, bool> _shown = {};

  static bool shownFor(String room) => _shown[room] ?? true;

  static void remember(String room, bool shown) => _shown[room] = shown;

  @visibleForTesting
  static void clear() => _shown.clear();
}

/// What the toggle says about the recording while the controls are hidden: nothing, recording (red dot), paused
/// (amber pause glyph), or — for the person who may record — not recording yet (the same pause glyph, muted).
enum LiveOverlayRec { none, recording, paused, notYet }

class LiveStageOverlay extends StatelessWidget {
  const LiveStageOverlay({
    super.key,
    required this.shown,
    required this.onToggle,
    this.top,
    this.bottom,
    this.rec = LiveOverlayRec.none,
    this.onActivity,
  });

  /// The controls are on screen.
  final bool shown;
  final VoidCallback onToggle;

  /// The room's top row (with its own padding).
  final Widget? top;

  /// The control bar (and the board's dock above it).
  final Widget? bottom;

  /// The recording state the toggle shows while the controls are hidden.
  final LiveOverlayRec rec;

  /// A touch on a bar.
  final VoidCallback? onActivity;

  @override
  Widget build(BuildContext context) {
    final dur = AppMotion.of(context).base;

    Widget bar(Widget child, {required bool atTop}) {
      final scrim = LinearGradient(
        begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
        end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [LivePalette.shade(0.55), LivePalette.shade(0.22), LivePalette.shade(0)],
        stops: const [0, 0.65, 1],
      );
      return ExcludeSemantics(
        excluding: !shown,
        child: IgnorePointer(
          ignoring: !shown,
          child: ClipRect(
            child: AnimatedAlign(
              duration: dur,
              curve: Curves.easeOutCubic,
              alignment: atTop ? Alignment.bottomCenter : Alignment.topCenter,
              heightFactor: shown ? 1 : 0,
              child: AnimatedOpacity(
                opacity: shown ? 1 : 0,
                duration: dur,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => onActivity?.call(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: scrim),
                    child: SafeArea(
                      top: false, // the top group is inside the safe area as a whole (the toggle never jumps)
                      bottom: !atTop,
                      child: Padding(
                        padding: EdgeInsets.only(top: atTop ? 0 : AppSpace.sm, bottom: atTop ? AppSpace.xs : 0),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: [
      Positioned(
        key: const ValueKey('live_room.overlay_top'),
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (top != null) bar(top!, atTop: true),
            // The toggle sits under the top row and follows it up when the controls hide.
            LiveOverlayToggle(shown: shown, onTap: onToggle, rec: shown ? LiveOverlayRec.none : rec),
          ]),
        ),
      ),
      if (bottom != null)
        Positioned(
          key: const ValueKey('live_room.overlay_bottom'),
          bottom: 0,
          left: 0,
          right: 0,
          child: bar(bottom!, atTop: false),
        ),
    ]);
  }
}

/// The hide / show toggle: a small glass pill (34 px drawn, 48 px hit, ≥ 64 px wide) with an eye and a chevron;
/// a label from 600 px of width; the recording's dot / pause glyph while the controls are hidden.
class LiveOverlayToggle extends StatelessWidget {
  const LiveOverlayToggle({super.key, required this.shown, required this.onTap, this.rec = LiveOverlayRec.none});

  final bool shown;
  final VoidCallback onTap;
  final LiveOverlayRec rec;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final action = shown ? t('إخفاء الأزرار', 'Hide controls') : t('إظهار الأزرار', 'Show controls');
    final recText = switch (rec) {
      LiveOverlayRec.recording => t('يُسجَّل', 'Recording'),
      LiveOverlayRec.paused => t('التسجيل متوقف مؤقتًا', 'Recording paused'),
      LiveOverlayRec.notYet => t('لا يُسجَّل بعد', 'Not recording yet'),
      LiveOverlayRec.none => null,
    };
    final style = TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: LivePalette.textHigh);
    return Semantics(
      button: true,
      label: recText == null ? action : '$action · $recText',
      excludeSemantics: true,
      child: Tooltip(
        message: action,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          key: const ValueKey('live_room.overlay_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height, minWidth: 64),
            child: Center(
              widthFactor: 1,
              child: Container(
                height: 34,
                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 12, 0),
                decoration: BoxDecoration(
                  color: LivePalette.shade(shown ? 0.45 : 0.6),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: LivePalette.glassBorder),
                  boxShadow: [BoxShadow(color: LivePalette.shade(0.25), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (rec == LiveOverlayRec.recording) ...[
                    Container(
                      key: const ValueKey('live_room.overlay_rec'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: LivePalette.danger),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (rec == LiveOverlayRec.paused || rec == LiveOverlayRec.notYet) ...[
                    Icon(Icons.pause_rounded,
                        key: const ValueKey('live_room.overlay_rec'),
                        size: 16,
                        color: rec == LiveOverlayRec.paused ? LivePalette.warning : LivePalette.warning.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                  ],
                  Icon(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: LivePalette.textHigh),
                  if (wide) ...[
                    const SizedBox(width: 6),
                    Flexible(child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
                  ],
                  const SizedBox(width: 2),
                  Icon(shown ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18, color: LivePalette.ink(0.8)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
