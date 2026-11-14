// lib/features/live/live_share_widgets.dart
//
// The widgets of "one share at a time" + "Request to share" and of the room's attention cues — presentational
// (plain values + callbacks) so the layout harness pumps them (test/ui/live_share_widgets_layout_test.dart), plus
// the thin dialog that binds the request card to the LiveShareArbiter. Drawn over the always-dark room: the
// LivePalette tokens (a deep shade of the app's primary), never hard-coded colours.
//
//   LiveShareRequestCard     "<name> wants to share their screen": the person's photo inside a ring that drains
//                            with the 30 s the request lasts, what Accept will do (your share stops / theirs
//                            starts), "+2 more waiting", Decline · Accept (busy while the permission call runs).
//   LiveShareRequestDialog   the card for the arbiter's current request; follows it (the next request, another
//                            host answered, it expired → it closes by itself). Back does not dismiss it.
//   LiveStopShareChip        the host's "Stop share" on a participant's share on the stage.
//   LiveChatToast            a new chat message while the chat is closed: who, two lines, tap → the chat;
//                            swipe or × hides it.
//   LiveChatToastSlot        the toast's place in the room with its enter / leave motion (none under Reduce motion).
//   LiveAttentionBadge       the count bubble (the bar's buttons, the minimized box); pops in when it grows.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/room/widgets/live_avatar.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/live_share_arbiter.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

TextStyle _text(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c ?? LivePalette.textHigh, height: h);

// ─────────────────────────────────────────────────────────────────────────────
// Request card
// ─────────────────────────────────────────────────────────────────────────────

/// What Accept does to the share that runs now.
enum LiveShareAcceptNote {
  /// Nobody shares: the requester starts.
  none,

  /// This host shares: it stops, theirs starts.
  yours,

  /// Someone else shares ([LiveShareRequestCard.presenterName]): theirs stops.
  other,
}

class LiveShareRequestCard extends StatelessWidget {
  const LiveShareRequestCard({
    super.key,
    required this.name,
    required this.onAccept,
    required this.onReject,
    this.imageUrl,
    this.remaining = kLiveShareRequestTtl,
    this.total = kLiveShareRequestTtl,
    this.othersWaiting = 0,
    this.note = LiveShareAcceptNote.none,
    this.presenterName = '',
    this.busy = false,
  });

  final String name;
  final String? imageUrl;
  final Duration remaining;
  final Duration total;
  final int othersWaiting;
  final LiveShareAcceptNote note;
  final String presenterName;

  /// Accept is in flight (the permission call, my share stopping).
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  String get _noteText => switch (note) {
        LiveShareAcceptNote.yours =>
          t('عند القبول تتوقف مشاركة شاشتك وتبدأ مشاركته.', 'Accepting stops your screen share and starts theirs.'),
        LiveShareAcceptNote.other => t('عند القبول تتوقف مشاركة $presenterName وتبدأ مشاركته.',
            "Accepting stops $presenterName's share and starts theirs."),
        LiveShareAcceptNote.none =>
          t('يمكنك إيقاف مشاركته في أي وقت.', 'You can stop their share at any time.'),
      };

  @override
  Widget build(BuildContext context) {
    final secs = remaining.inSeconds.clamp(0, 999);
    final fraction = total.inMilliseconds <= 0 ? 0.0 : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final accent = LivePalette.accent;
    return Semantics(
      container: true,
      label: t('طلب مشاركة الشاشة', 'Screen share request'),
      child: Container(
        key: const ValueKey('live_share.request_card'),
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        decoration: BoxDecoration(
          color: LivePalette.surfaceHi,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: LivePalette.glassBorder),
          boxShadow: [
            BoxShadow(color: LivePalette.shade(0.4), blurRadius: 40, offset: const Offset(0, 12)),
            BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 32),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _CountdownAvatar(name: name, imageUrl: imageUrl, fraction: fraction),
          const SizedBox(height: 16),
          Text(
            t('يطلب $name مشاركة شاشته', '$name wants to share their screen'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _text(17, w: FontWeight.w800, h: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            _noteText,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _text(13.5, c: LivePalette.textMid, h: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(
                icon: Icons.timer_outlined,
                label: t('ينتهي خلال $secs ث', 'Expires in ${secs}s'),
                color: secs <= 5 ? LivePalette.warning : LivePalette.textMid,
              ),
              if (othersWaiting > 0)
                _MetaPill(
                  icon: Icons.people_alt_outlined,
                  label: t('+$othersWaiting بانتظار الرد', '+$othersWaiting more waiting'),
                  color: LivePalette.textMid,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: _DialogButton(
                key: const ValueKey('live_share.reject'),
                label: t('رفض', 'Decline'),
                onTap: busy ? null : onReject,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DialogButton(
                key: const ValueKey('live_share.accept'),
                label: t('قبول', 'Accept'),
                icon: Icons.screen_share_rounded,
                filled: true,
                busy: busy,
                onTap: busy ? null : onAccept,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The requester's photo inside a ring that drains with the time left (smoothly; per second under Reduce motion).
class _CountdownAvatar extends StatelessWidget {
  const _CountdownAvatar({required this.name, required this.imageUrl, required this.fraction});
  final String name;
  final String? imageUrl;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final accent = LivePalette.accent;
    final ring = TweenAnimationBuilder<double>(
      tween: Tween(end: fraction),
      duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 950),
      curve: Curves.linear,
      builder: (_, v, _) => CustomPaint(
        size: const Size.square(size + 16),
        painter: _RingPainter(
          fraction: v,
          track: LivePalette.glassBorder,
          color: fraction <= 0.17 ? LivePalette.warning : accent,
        ),
      ),
    );
    return SizedBox(
      width: size + 16,
      height: size + 16,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        ring,
        LiveAvatar(name: name, imageUrl: imageUrl, size: size, ring: false, shadow: false),
        PositionedDirectional(
          bottom: 4,
          end: 4,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              border: Border.all(color: LivePalette.surfaceHi, width: 2.5),
            ),
            child: Icon(Icons.screen_share_rounded, size: 14, color: LivePalette.bg),
          ),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.color});
  final double fraction;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2 + 1);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    if (fraction <= 0) return;
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * fraction, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: LivePalette.glassFaint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LivePalette.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(12, w: FontWeight.w700, c: color)),
          ),
        ]),
      );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({super.key, required this.label, required this.onTap, this.icon, this.filled = false, this.busy = false});
  final String label;
  final IconData? icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LivePalette.accent;
    final fg = filled ? LivePalette.bg : LivePalette.textHigh;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? accent : LivePalette.glass,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled ? null : Border.all(color: LivePalette.glassBorder),
            ),
            child: busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
                    Flexible(
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(14.5, w: FontWeight.w800, c: fg)),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The dialog bound to the arbiter
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the request dialog over the room (once; it shows request after request and closes itself).
Future<void> showLiveShareRequestDialog(
  BuildContext context, {
  required LiveShareArbiter arbiter,
  required void Function(LiveShareRequest request, bool accept) onAnswer,
  required (LiveShareAcceptNote, String) Function() note,
  String? Function(LiveShareRequest request)? imageFor,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: LivePalette.shade(0.55),
      builder: (_) => LiveShareRequestDialog(arbiter: arbiter, onAnswer: onAnswer, note: note, imageFor: imageFor),
    );

class LiveShareRequestDialog extends StatefulWidget {
  const LiveShareRequestDialog({super.key, required this.arbiter, required this.onAnswer, required this.note, this.imageFor});

  final LiveShareArbiter arbiter;
  final void Function(LiveShareRequest request, bool accept) onAnswer;

  /// What Accept does now (asked on every rebuild: a share may start or stop while the dialog is open).
  final (LiveShareAcceptNote, String) Function() note;
  final String? Function(LiveShareRequest request)? imageFor;

  @override
  State<LiveShareRequestDialog> createState() => _LiveShareRequestDialogState();
}

class _LiveShareRequestDialogState extends State<LiveShareRequestDialog> {
  Timer? _clock;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.arbiter.addListener(_onChange);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    if (!mounted) return;
    if (widget.arbiter.current == null) {
      _close();
    } else {
      setState(() {});
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _clock?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.arbiter.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.arbiter;
    final r = a.current;
    final (note, presenter) = widget.note();
    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedSwitcher(
              duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
              ),
              child: r == null
                  ? const SizedBox.shrink()
                  : LiveShareRequestCard(
                      key: ValueKey('live_share.request.${r.id}'),
                      name: r.name,
                      imageUrl: widget.imageFor?.call(r) ?? r.imageUrl,
                      remaining: r.remaining(DateTime.now()),
                      othersWaiting: (a.pendingCount - 1).clamp(0, 99),
                      note: note,
                      presenterName: presenter,
                      busy: a.answering(r.id),
                      onAccept: () => widget.onAnswer(r, true),
                      onReject: () => widget.onAnswer(r, false),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stop share chip (host, on a participant's share)
// ─────────────────────────────────────────────────────────────────────────────

class LiveStopShareChip extends StatelessWidget {
  const LiveStopShareChip({super.key, required this.onTap, this.busy = false});
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final red = LivePalette.danger;
    final label = t('إيقاف المشاركة', 'Stop share');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('live_share.stop_chip'),
        color: Color.alphaBlend(red.withValues(alpha: 0.24), LivePalette.shade(0.55)),
        shape: StadiumBorder(side: BorderSide(color: red.withValues(alpha: 0.65))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: LivePalette.textHigh))
                    : const Icon(Icons.stop_screen_share_rounded, size: 16, color: LivePalette.textHigh),
                const SizedBox(width: 8),
                Text(label, maxLines: 1, style: _text(12.5, w: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat toast
// ─────────────────────────────────────────────────────────────────────────────

/// One message to preview.
class LiveChatToastData {
  const LiveChatToastData({required this.id, required this.name, required this.text, this.imageUrl, this.more = 0});
  final String id;
  final String name;
  final String text;
  final String? imageUrl;

  /// Other unread messages besides this one.
  final int more;
}

class LiveChatToast extends StatelessWidget {
  const LiveChatToast({super.key, required this.data, required this.onOpen, required this.onDismiss});
  final LiveChatToastData data;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final accent = LivePalette.accent;
    final more = data.more > 0 ? t('+${data.more} رسائل أخرى', '+${data.more} more') : null;
    return Semantics(
      button: true,
      label: t('رسالة من ${data.name}: ${data.text}. افتح المحادثة', 'Message from ${data.name}: ${data.text}. Open the chat'),
      excludeSemantics: true,
      child: Dismissible(
        key: ValueKey('live_chat.toast.${data.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: Material(
          key: const ValueKey('live_chat.toast'),
          color: LivePalette.surfaceHi.withValues(alpha: 0.96),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: LivePalette.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                border: BorderDirectional(start: BorderSide(color: accent, width: 3)),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 4, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LiveAvatar(name: data.name, imageUrl: data.imageUrl, size: 36, ring: false, shadow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Flexible(
                        child: Text(data.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(13, w: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chat_bubble_rounded, size: 12, color: accent),
                      if (more != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(more, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: _text(11.5, w: FontWeight.w700, c: LivePalette.textSoft)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(data.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: _text(13, c: LivePalette.textMid, h: 1.35)),
                  ]),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    key: const ValueKey('live_chat.toast.close'),
                    tooltip: t('إخفاء', 'Hide'),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded, color: LivePalette.textSoft),
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

/// The toast's slot: slides up and fades in, fades out (no motion under Reduce motion).
class LiveChatToastSlot extends StatelessWidget {
  const LiveChatToastSlot({super.key, required this.data, required this.onOpen, required this.onDismiss});
  final LiveChatToastData? data;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return AnimatedSwitcher(
      duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 240),
      reverseDuration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: d == null
          ? const SizedBox.shrink()
          : LiveChatToast(key: ValueKey('live_chat.toast_slot.${d.id}'), data: d, onOpen: onOpen, onDismiss: onDismiss),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attention badge
// ─────────────────────────────────────────────────────────────────────────────

/// The count bubble. Pops in when the count grows (a still bubble under Reduce motion); 0 draws nothing.
class LiveAttentionBadge extends StatelessWidget {
  const LiveAttentionBadge({super.key, required this.count, this.size = 18});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final c = LivePalette.danger;
    final bubble = Container(
      key: const ValueKey('live.attention_badge'),
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: LivePalette.surfaceHi, width: 1.5),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 8)],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: _text(size * 0.56, w: FontWeight.w800, h: 1.1),
      ),
    );
    if (_reduceMotion(context)) return bubble;
    return TweenAnimationBuilder<double>(
      key: ValueKey('live.attention_badge.$count'),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: bubble,
    );
  }
}
