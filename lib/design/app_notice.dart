// lib/design/app_notice.dart
//
// Messages that are ALWAYS visible: drawn in the root Navigator's overlay, above every page, bottom sheet and
// dialog (a SnackBar lives inside the page's Scaffold, so an open sheet / dialog covered it).
// Top of the screen (the keyboard never hides it), theme colours, page direction, auto-dismiss, tap to close.
// A layer painted ABOVE the root Navigator (the full-screen live room, D-059) registers its own overlay in
// [appNoticeTopOverlay], so a notice raised there is not hidden behind it.
//
//   showAppNotice('Saved');                       showAppNotice('Could not save', error: true);
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

OverlayEntry? _current;
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
/// [icon] replaces the default check / error mark.
bool showAppNotice(String message,
    {bool error = false, IconData? icon, Duration duration = const Duration(milliseconds: 3200)}) {
  final overlay = _noticeOverlay();
  if (overlay == null || message.trim().isEmpty) return false;
  _timer?.cancel();
  _current?.remove();
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (ctx) => _Notice(message: message, error: error, icon: icon, onClose: () {
        if (_current == entry) {
          _current = null;
          entry.remove();
        }
      }));
  _current = entry;
  _currentMessage = message;
  overlay.insert(entry);                         // last child of the root overlay = above every route
  _timer = Timer(duration, () {
    if (_current == entry) {
      _current = null;
      entry.remove();
    }
  });
  return true;
}

/// Removes the notice on screen — only when it still shows [message], if given (a later notice stays).
void hideAppNotice({String? message}) {
  final entry = _current;
  if (entry == null || (message != null && message != _currentMessage)) return;
  _timer?.cancel();
  _current = null;
  entry.remove();
}

class _Notice extends StatefulWidget {
  const _Notice({required this.message, required this.error, required this.onClose, this.icon});
  final String message;
  final bool error;
  final IconData? icon;
  final VoidCallback onClose;

  @override
  State<_Notice> createState() => _NoticeState();
}

class _NoticeState extends State<_Notice> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = widget.error ? c.danger : c.success;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(CurvedAnimation(parent: _a, curve: Curves.easeOutBack)),
            child: FadeTransition(
              opacity: _a,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: tone.withValues(alpha: 0.35)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), shape: BoxShape.circle),
                            child: Icon(widget.icon ?? (widget.error ? Icons.error_rounded : Icons.check_circle_rounded), color: tone, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(widget.message, maxLines: 4, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w600, color: c.textDark, height: 1.35)),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.close_rounded, size: 18, color: c.textLight),
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
    );
  }
}
