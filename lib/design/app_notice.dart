// lib/design/app_notice.dart
//
// Messages that are ALWAYS visible: drawn in the root Navigator's overlay, above every page, bottom sheet and
// dialog (a SnackBar lives inside the page's Scaffold, so an open sheet / dialog covered it).
// Top of the screen (the keyboard never hides it), theme colours, page direction, auto-dismiss, tap to close.
// A layer painted ABOVE the root Navigator (the full-screen live room, D-059) registers its own overlay in
// [appNoticeTopOverlay], so a notice raised there is not hidden behind it.
//
// Look (D-612): ink on paper — the card surface, the row type role, a leading mark in emerald (done) or danger
// (failed) inside a tinted circle, the overlay shadow in the warm tone. Motion (D-621): it slides down from the top
// edge in 260 ms on `AppEase.out` and leaves upward in 180 ms; a finger can drag it (1:1, friction below its rest)
// and a flick or a drag past half its height dismisses it the way it came. Reduce motion: it appears and leaves
// at once.
//
//   showAppNotice('Saved');                       showAppNotice('Could not save', error: true);
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/helpers.dart';

import 'app_motion_kit.dart' show AppEase, appMotionOff;
import 'app_tokens.dart';

OverlayEntry? _current;
GlobalKey<_NoticeState>? _currentKey;
String? _currentMessage;
Timer? _timer;

/// The overlay of a layer that currently covers the app Navigator (LiveRoomLayer while a room is full-screen), or
/// null. Notices go there instead of the root overlay, which that layer would hide.
OverlayState? Function()? appNoticeTopOverlay;

OverlayState? _noticeOverlay() {
  final top = appNoticeTopOverlay?.call();
  if (top != null && top.mounted) return top;
  return navigatorKey.currentState?.overlay;
}

/// Returns false when there is no overlay yet (very early start-up) — callers may fall back to a SnackBar.
/// [icon] replaces the default check / error mark. [actionLabel] + [onAction] add one text button (e.g. "Undo") that
/// closes the notice and runs the action; such a notice stays a little longer (6 s) unless [duration] is given.
bool showAppNotice(String message,
    {bool error = false, IconData? icon, Duration? duration, String? actionLabel, VoidCallback? onAction}) {
  final overlay = _noticeOverlay();
  if (overlay == null || message.trim().isEmpty) return false;
  _timer?.cancel();
  // the one before goes at once: the new message is what matters now
  _current?.remove();
  _current = null;
  late OverlayEntry entry;
  final key = GlobalKey<_NoticeState>();
  void close() => _dismiss(entry, key);

  entry = OverlayEntry(builder: (ctx) => _Notice(
        key: key,
        message: message,
        error: error,
        icon: icon,
        onClose: close,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction == null
            ? null
            : () {
                close();
                onAction();
              },
      ));
  _current = entry;
  _currentKey = key;
  _currentMessage = message;
  overlay.insert(entry);                         // last child of the root overlay = above every route
  _timer = Timer(duration ?? Duration(milliseconds: onAction != null ? 6000 : 3200), close);
  return true;
}

/// Removes the notice on screen — only when it still shows [message], if given (a later notice stays).
void hideAppNotice({String? message}) {
  final entry = _current;
  final key = _currentKey;
  if (entry == null || key == null || (message != null && message != _currentMessage)) return;
  _dismiss(entry, key);
}

/// Plays the exit (when the notice is still on screen and motion is on), then takes the entry out of the overlay.
Future<void> _dismiss(OverlayEntry entry, GlobalKey<_NoticeState> key) async {
  if (_current != entry) return;
  _timer?.cancel();
  _current = null;
  _currentKey = null;
  final state = key.currentState;
  if (state != null && state.mounted) await state.leave();
  if (entry.mounted) entry.remove();
}

class _Notice extends StatefulWidget {
  const _Notice({super.key, required this.message, required this.error, required this.onClose, this.icon, this.actionLabel, this.onAction});
  final String message;
  final bool error;
  final IconData? icon;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_Notice> createState() => _NoticeState();
}

class _NoticeState extends State<_Notice> with TickerProviderStateMixin {
  static const Duration _in = Duration(milliseconds: 260);
  static const Duration _out = Duration(milliseconds: 180);
  static const Duration _snapBack = Duration(milliseconds: 200);

  /// The widest a notice gets: one comfortable line of text beside its mark.
  static const double maxWidth = 560;

  /// How far above its rest the notice starts and ends, in its own height.
  static const double _travel = 1.2;

  late final AnimationController _a = AnimationController(vsync: this, duration: _in, reverseDuration: _out);
  late final CurvedAnimation _curved = CurvedAnimation(parent: _a, curve: AppEase.out, reverseCurve: AppEase.outReversed);
  late final AnimationController _snap = AnimationController(vsync: this, duration: _snapBack);

  /// The finger's travel since the drag started (negative = toward the top edge).
  double _raw = 0;

  /// Where the last drag let go, while [_snap] brings it back to rest.
  double _snapFrom = 0;
  bool _reduce = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduce = appMotionOff(context);
    if (_reduce) {
      _a.value = 1;
    } else {
      _a.forward();
    }
  }

  /// Runs the exit from wherever the notice is now (a drag's offset stays, so it leaves along the same line).
  Future<void> leave() async {
    if (_reduce) {
      _a.value = 0;
      return;
    }
    try {
      await _a.reverse().orCancel;
    } on TickerCanceled {
      // disposed mid-way: the entry is going anyway
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _a.dispose();
    _snap.dispose();
    super.dispose();
  }

  /// The drawn offset: the finger's own travel upward, a quarter of it downward (there is nothing further).
  double get _dragOffset {
    if (_snap.isAnimating) return _snapFrom * (1 - AppEase.out.transform(_snap.value));
    return _raw < 0 ? _raw : _raw * 0.25;
  }

  void _onDragStart(DragStartDetails _) {
    _snap.stop();
    _raw = _dragOffset;
  }

  void _onDragUpdate(DragUpdateDetails d) => setState(() => _raw += d.delta.dy);

  void _onDragEnd(DragEndDetails d) {
    final flick = d.velocity.pixelsPerSecond.dy < -_flickSpeed;
    if (_raw < -_dismissDistance || (flick && _raw < 0)) {
      widget.onClose();
      return;
    }
    _snapFrom = _dragOffset;
    _raw = 0;
    if (_reduce) {
      setState(() {});
      return;
    }
    _snap.forward(from: 0);
  }

  /// Faster than this upward and a short drag still dismisses (px/s).
  static const double _flickSpeed = 600;

  /// A slow drag dismisses once it has lifted the notice this far: about half its own height.
  static const double _dismissDistance = AppSpace.xl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = widget.error ? c.danger : c.success;
    final toneTint = widget.error ? c.dangerTint : c.successTint;
    final curved = _curved;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: Listenable.merge([_a, _snap]),
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _dragOffset),
              child: FractionalTranslation(
                translation: Offset(0, -_travel * (1 - curved.value)),
                child: Opacity(opacity: curved.value.clamp(0.0, 1.0), child: child),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          borderRadius: AppRadius.cardAll,
                          border: AppElevation.border(context, 3),
                          boxShadow: AppElevation.of(context, 3),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
                          child: Row(children: [
                            SizedBox(
                              width: AppIconSize.xl,
                              height: AppIconSize.xl,
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: toneTint, shape: BoxShape.circle),
                                child: Icon(
                                  widget.icon ?? (widget.error ? Icons.error_rounded : Icons.check_circle_rounded),
                                  color: tone,
                                  size: AppIconSize.md,
                                ),
                              ),
                            ),
                            AppSpace.gapSm,
                            Expanded(
                              child: Text(widget.message,
                                  maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                            ),
                            if (widget.actionLabel != null && widget.onAction != null) ...[
                              AppSpace.gapXs,
                              TextButton(
                                onPressed: widget.onAction,
                                style: TextButton.styleFrom(
                                    minimumSize: const Size(AppTouch.min, AppTouch.min - AppSpace.xxs),
                                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm)),
                                child: Text(widget.actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            AppSpace.gapXs,
                            Icon(Icons.close_rounded, size: AppIconSize.sm, color: c.textLight),
                          ]),
                        ),
                      ),
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
}
