// lib/features/teacher/sessions/live/widgets/live_focus_chrome.dart
//
// Full view's bars (D-108). In full view room.dart draws ONLY the shared content (a shared screen, the whiteboard
// page, or the presenter's camera when nothing is shared — with the presenter's camera box over a share / board,
// which is part of what is presented); the top row, the bottom bar, the thumbnails, the side panels and my own
// camera box step aside. A tap on the content calls [LiveFocusChrome.shown] true: the top row slides down from the
// top edge and the bar up from the bottom (slide + fade, 200 ms; at once under Reduce motion), OVER the content —
// the content never moves. Another tap hides them; so does [onActivity]'s 4 s idle timer in room.dart. A short
// hint says how to get them ([hint]) when full view opens.
//
// Drawing in full view (D-108, round 7): on a board this person may draw on, a tap on the page is a dot of ink, so it
// cannot also mean "the controls". [handle] then draws a small glass "Controls" chip at the top centre while the bars
// are hidden ([LiveFocusHandle]); its tap shows them ([onHandle]) — the board's tool dock comes with the bottom bar.
// Everyone who is not drawing keeps the tap.
//
// Plain values (the two bars come in as widgets), so test/ui/live_focus_chrome_layout_test.dart pumps it with the
// layout harness and test/visual/live_top_row_golden_test.dart renders it shown and hidden.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemUiMode;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'live_palette.dart';

/// How long the bars slide.
const Duration kLiveFocusChromeDuration = Duration(milliseconds: 200);

/// How long the bars stay after the last touch on them.
const Duration kLiveFocusChromeIdle = Duration(seconds: 4);

/// What a tap on the content does to the bars in full view: shows them when hidden, hides them when shown.
bool liveFocusBarsAfterTap(bool shown) => !shown;

/// D-306: what full view asks of a phone / tablet — the system bars away (immersive: a swipe from the edge brings
/// them back for a moment) and every orientation, so the shared page or screen takes the whole display and turns
/// with the device; leaving it gives both back (edge-to-edge, every orientation: the app's own default). Null off a
/// phone / tablet (the web and desktop have no system bars to hide). The room applies it in room.dart
/// (`_syncFocusSystemUi`); the safe area (a camera cut-out, rounded corners) still pads the content.
({SystemUiMode mode, List<DeviceOrientation> orientations})? liveFullViewSystemUi({required bool on, required bool mobile}) {
  if (!mobile) return null;
  return (mode: on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge, orientations: DeviceOrientation.values);
}

class LiveFocusChrome extends StatelessWidget {
  const LiveFocusChrome({
    super.key,
    required this.shown,
    this.top,
    this.bottom,
    this.hint = false,
    this.onActivity,
    this.handle = false,
    this.onHandle,
  });

  /// The bars are on screen.
  final bool shown;

  /// The room's top row (with its own padding).
  final Widget? top;

  /// The room's control bar.
  final Widget? bottom;

  /// "Tap the screen to show the controls" (the first seconds of full view).
  final bool hint;

  /// A touch on a bar (room.dart restarts the idle timer).
  final VoidCallback? onActivity;

  /// The "Controls" chip while the bars are hidden: the person draws on the page, where a tap is ink.
  final bool handle;

  /// The chip's tap: show the bars.
  final VoidCallback? onHandle;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dur = still ? Duration.zero : kLiveFocusChromeDuration;

    Widget bar(Widget child, {required bool atTop}) {
      final scrim = LinearGradient(
        begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
        end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [LivePalette.shade(0.62), LivePalette.shade(0.30), LivePalette.shade(0)],
        stops: const [0, 0.6, 1],
      );
      return ExcludeSemantics(
        excluding: !shown,
        child: IgnorePointer(
          ignoring: !shown,
          child: AnimatedSlide(
            offset: shown ? Offset.zero : Offset(0, atTop ? -1 : 1),
            duration: dur,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: dur,
              curve: Curves.easeOut,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => onActivity?.call(),
                onPointerHover: (_) => onActivity?.call(),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: scrim),
                  child: SafeArea(
                    top: atTop,
                    bottom: !atTop,
                    child: Padding(padding: EdgeInsets.only(top: atTop ? 0 : 14, bottom: atTop ? 14 : 0), child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: [
      if (top != null) Positioned(key: const ValueKey('live_room.focus_top'), top: 0, left: 0, right: 0, child: bar(top!, atTop: true)),
      if (bottom != null)
        Positioned(key: const ValueKey('live_room.focus_bottom'), bottom: 0, left: 0, right: 0, child: bar(bottom!, atTop: false)),
      if (handle)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ExcludeSemantics(
                excluding: shown,
                child: IgnorePointer(
                  ignoring: shown,
                  child: AnimatedOpacity(
                    opacity: shown ? 0 : 1,
                    duration: dur,
                    child: LiveFocusHandle(onTap: onHandle),
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: 16,
        right: 16,
        top: handle ? 16 + LiveFocusHandle.height : 16, // under the chip; clear of the camera box (bottom corner)
        child: SafeArea(
          bottom: false,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: hint && !shown ? 1 : 0,
                duration: still ? Duration.zero : const Duration(milliseconds: 260),
                child: LiveFocusHint(visible: hint && !shown, drawing: handle),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Tap the screen to show the controls" — or, while drawing ([drawing]), where the controls are instead.
class LiveFocusHint extends StatelessWidget {
  const LiveFocusHint({super.key, this.visible = true, this.drawing = false});
  final bool visible;
  final bool drawing;

  @override
  Widget build(BuildContext context) {
    final text = drawing
        ? t('ارسم على السبورة · زر «الأزرار» في الأعلى يُظهرها', 'Draw on the board · Controls at the top shows them')
        : t('اضغط على الشاشة لإظهار الأزرار', 'Tap the screen to show the controls');
    return Semantics(
      liveRegion: visible,
      label: visible ? text : null,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('live_room.focus_hint'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: LivePalette.shade(0.62),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LivePalette.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(drawing ? Icons.draw_rounded : Icons.touch_app_rounded, size: 17, color: LivePalette.textHigh),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: LivePalette.textHigh),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full view's "Controls" chip (D-108): a small glass pill at the top centre while this person draws on the board.
/// Drawn 34 px tall, hit 48 px tall and at least 64 px wide.
class LiveFocusHandle extends StatelessWidget {
  const LiveFocusHandle({super.key, this.onTap});

  final VoidCallback? onTap;

  /// The chip's hit height (px).
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final label = t('الأزرار', 'Controls');
    return Semantics(
      button: true,
      label: t('إظهار الأزرار', 'Show the controls'),
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('live_room.focus_handle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height, minWidth: 64),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 34,
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 14, 0),
              decoration: BoxDecoration(
                color: LivePalette.shade(0.55),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: LivePalette.glassBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: LivePalette.textHigh),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: LivePalette.textHigh),
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
