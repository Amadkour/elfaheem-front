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
// Plain values (the two bars come in as widgets), so test/ui/live_focus_chrome_layout_test.dart pumps it with the
// layout harness and test/visual/live_top_row_golden_test.dart renders it shown and hidden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'live_palette.dart';

/// How long the bars slide.
const Duration kLiveFocusChromeDuration = Duration(milliseconds: 200);

/// How long the bars stay after the last touch on them.
const Duration kLiveFocusChromeIdle = Duration(seconds: 4);

/// What a tap on the content does to the bars in full view: shows them when hidden, hides them when shown.
bool liveFocusBarsAfterTap(bool shown) => !shown;

class LiveFocusChrome extends StatelessWidget {
  const LiveFocusChrome({
    super.key,
    required this.shown,
    this.top,
    this.bottom,
    this.hint = false,
    this.onActivity,
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
      Positioned(
        left: 16,
        right: 16,
        top: 16, // clear of the presenter's camera box (bottom corner by default)
        child: SafeArea(
          bottom: false,
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: hint && !shown ? 1 : 0,
                duration: still ? Duration.zero : const Duration(milliseconds: 260),
                child: LiveFocusHint(visible: hint && !shown),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Tap the screen to show the controls · Esc to exit".
class LiveFocusHint extends StatelessWidget {
  const LiveFocusHint({super.key, this.visible = true});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final text = t('اضغط على الشاشة لإظهار الأزرار', 'Tap the screen to show the controls');
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
          const Icon(Icons.touch_app_rounded, size: 17, color: LivePalette.textHigh),
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
