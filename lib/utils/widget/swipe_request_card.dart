/// swipe_request_card.dart
///
/// Shared building blocks for the teacher "review queue" screens
/// (payment transfers, device-switch requests):
///
///  • [SwipeRequestCard]   – a card that can be DRAGGED to accept (one way)
///                           or reject (other way). The item leaves the list
///                           with a slide + collapse animation. The same exit
///                           animation also plays when the buttons are used.
///  • [RequestCardShell], [RequestAvatar], [RequestInfoRow],
///    [RequestActionButtons], [SwipeHintBanner], [RequestStateView]
///                         – the premium look shared by both screens.
///  • [showReasonDialog]   – rejection reason dialog (with quick reasons).
///  • [showRequestSnack]   – floating result toast.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Swipe card
// ─────────────────────────────────────────────────────────────────────────────

/// Handed to the card content so its buttons share the exact same flow
/// (busy state → API call → exit animation → removal) as the swipe gesture.
class SwipeCardController {
  const SwipeCardController({
    required this.busy,
    required this.approve,
    required this.reject,
  });

  final bool busy;
  final Future<void> Function() approve;
  final Future<void> Function() reject;
}

typedef SwipeCardBuilder =
Widget Function(BuildContext context, SwipeCardController ctl);

class SwipeRequestCard extends StatefulWidget {
  const SwipeRequestCard({
    super.key,
    required this.itemId,
    required this.builder,
    required this.onApprove,
    required this.onReject,
    required this.onRemoved,
    this.approveLabel,
    this.rejectLabel,
  });

  /// Stable id of the item (used as the Dismissible key).
  final Object itemId;

  final SwipeCardBuilder builder;

  /// Performs the approve call. Return true on success. The item must NOT be
  /// removed from the list here — [onRemoved] does that once the exit
  /// animation has finished.
  final Future<bool> Function() onApprove;

  /// Performs the reject flow (ask for a reason, call the API). Return false
  /// if the teacher cancelled or the call failed — the card springs back.
  final Future<bool> Function() onReject;

  /// Called when the exit animation is done: remove the item from the list.
  final VoidCallback onRemoved;

  /// Defaults to 'request_accept'.tr / 'request_reject'.tr.
  final String? approveLabel;
  final String? rejectLabel;

  @override
  State<SwipeRequestCard> createState() => _SwipeRequestCardState();
}

class _SwipeRequestCardState extends State<SwipeRequestCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _busy = false;
  double _exitDx = 1;

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  /// Runs [action] once at a time and tracks the busy state.
  Future<bool> _guard(Future<bool> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return ok;
  }

  /// Button path: same result as a swipe, animated by us.
  Future<void> _viaButton(
      bool approve,
      Future<bool> Function() action,
      ) async {
    final ok = await _guard(action);
    if (!ok || !mounted) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _exitDx = (approve ? 1.0 : -1.0) * (rtl ? -1.0 : 1.0);
    HapticFeedback.lightImpact();
    await _exit.forward();
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final ctl = SwipeCardController(
      busy: _busy,
      approve: () => _viaButton(true, widget.onApprove),
      reject: () => _viaButton(false, widget.onReject),
    );

    final dismissible = Dismissible(
      key: ValueKey(widget.itemId),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      movementDuration: const Duration(milliseconds: 220),
      resizeDuration: const Duration(milliseconds: 320),
      background: _SwipeBackground(
        color: c.success,
        icon: Icons.check_circle_rounded,
        label: widget.approveLabel ?? 'request_accept'.tr,
        alignment: AlignmentDirectional.centerStart,
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
      ),
      secondaryBackground: _SwipeBackground(
        color: c.danger,
        icon: Icons.cancel_rounded,
        label: widget.rejectLabel ?? 'request_reject'.tr,
        alignment: AlignmentDirectional.centerEnd,
        begin: AlignmentDirectional.centerEnd,
        end: AlignmentDirectional.centerStart,
      ),
      onUpdate: (d) {
        // Tiny tick when the drag passes the "will be dismissed" threshold.
        if (d.reached && !d.previousReached) HapticFeedback.selectionClick();
      },
      confirmDismiss: (direction) => _guard(
        direction == DismissDirection.startToEnd
            ? widget.onApprove
            : widget.onReject,
      ),
      onDismissed: (_) => widget.onRemoved(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: widget.builder(context, ctl),
      ),
    );

    return AnimatedBuilder(
      animation: _exit,
      child: dismissible,
      builder: (context, child) {
        final t = _exit.value;
        if (t == 0) return child!;
        final slideT = Curves.easeInCubic.transform((t / 0.6).clamp(0.0, 1.0));
        final sizeT = Curves.easeInOutCubic.transform(
          ((t - 0.5) / 0.5).clamp(0.0, 1.0),
        );
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: (1 - sizeT).clamp(0.0, 1.0),
            child: Opacity(
              opacity: (1 - slideT).clamp(0.0, 1.0),
              child: FractionalTranslation(
                translation: Offset(_exitDx * slideT, 0),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
    required this.begin,
    required this.end,
  });

  final Color color;
  final IconData icon;
  final String label;
  final AlignmentGeometry alignment;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: [color, color.withValues(alpha: 0.55)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium card pieces
// ─────────────────────────────────────────────────────────────────────────────

/// The card surface: rounded, soft shadow, gradient accent strip on top.
class RequestCardShell extends StatelessWidget {
  const RequestCardShell({
    super.key,
    required this.child,
    this.accent,
    this.busy = false,
  });

  final Widget child;
  final Color? accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = this.accent ?? c.primary;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: busy ? 0.65 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.divider),
          boxShadow: c.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.3)],
                  ),
                ),
              ),
              Padding(padding: const EdgeInsets.all(16), child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round gradient avatar with the first letter of the name.
class RequestAvatar extends StatelessWidget {
  const RequestAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first);
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.primary, c.primary.withValues(alpha: 0.6)],
        ),
      ),
      child: Text(
        initial,
        style: c.h3.copyWith(color: Colors.white, fontSize: 18),
      ),
    );
  }
}

/// Icon + small label + value. Tap copies the value when [copyable].
class RequestInfoRow extends StatelessWidget {
  const RequestInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: c.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: c.caption),
              Text(
                value,
                style: c.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textDark,
                ),
              ),
            ],
          ),
        ),
        if (copyable) Icon(Icons.copy_rounded, size: 16, color: c.textLight),
      ],
    );

    if (!copyable) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('copied_to_clipboard'.tr),
              duration: const Duration(seconds: 1),
            ),
          );
      },
      child: row,
    );
  }
}

/// Reject (outlined) + Approve (filled) buttons wired to the swipe flow.
class RequestActionButtons extends StatelessWidget {
  const RequestActionButtons({
    super.key,
    required this.ctl,
    this.approveLabel,
    this.rejectLabel,
  });

  final SwipeCardController ctl;
  final String? approveLabel;
  final String? rejectLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const textStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: ctl.busy ? null : ctl.reject,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(rejectLabel ?? 'request_reject'.tr),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger.withValues(alpha: 0.6)),
              minimumSize: const Size(0, 46),
              shape: shape,
              textStyle: textStyle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: ctl.busy ? null : ctl.approve,
            icon: ctl.busy
                ? const SizedBox(
              height: 16,
              child: AppLoadingIndicator(showLogo: false),
            )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(approveLabel ?? 'request_accept'.tr),
            style: FilledButton.styleFrom(
              backgroundColor: c.success,
              minimumSize: const Size(0, 46),
              shape: shape,
              textStyle: textStyle,
            ),
          ),
        ),
      ],
    );
  }
}

/// List header: pending count + which way to drag. The sides are computed
/// from the current text direction, so the wording is right in RTL and LTR.
class SwipeHintBanner extends StatelessWidget {
  const SwipeHintBanner({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Approve = drag from start towards end (physically left in RTL).
    final hint = rtl ? 'swipe_hint_accept_left'.tr : 'swipe_hint_accept_right'.tr;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.swipe_rounded, color: c.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${'requests_pending_review'.tr}',
                    style: c.label.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: c.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty / error state, inside a scrollable so pull-to-refresh still works.
class RequestStateView extends StatelessWidget {
  const RequestStateView({
    super.key,
    required this.icon,
    required this.message,
    this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = this.color ?? c.primary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 90),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.1),
            ),
            child: Icon(icon, size: 40, color: color),
          ),
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: c.body),
        if (actionLabel != null) ...[
          const SizedBox(height: 14),
          Center(
            child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog + toast helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Asks for the rejection reason. Returns null when cancelled; otherwise the
/// trimmed text (can be '' only when [requireReason] is false).
Future<String?> showReasonDialog(
    BuildContext context, {
      required String title,
      required String hint,
      bool requireReason = true,
      List<String> quickReasons = const [],
    }) {
  // Dialogs live above the page's own Directionality: carry it over.
  final dir = Directionality.of(context);
  return showDialog<String>(
    context: context,
    builder: (_) => Directionality(
      textDirection: dir,
      child: _ReasonDialog(
        title: title,
        hint: hint,
        requireReason: requireReason,
        quickReasons: quickReasons,
      ),
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.requireReason,
    required this.quickReasons,
  });

  final String title;
  final String hint;
  final bool requireReason;
  final List<String> quickReasons;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => !widget.requireReason || _ctrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.report_gmailerrorred_rounded, color: c.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.quickReasons.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in widget.quickReasons)
                    ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        _ctrl.text = q;
                        _ctrl.selection = TextSelection.collapsed(
                          offset: q.length,
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctrl,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, _ctrl.text.trim())
              : null,
          style: FilledButton.styleFrom(backgroundColor: c.danger),
          child: Text('request_reject'.tr),
        ),
      ],
    );
  }
}

/// Floating result toast. Pass a messenger captured BEFORE any `await`.
void showRequestSnack(
    ScaffoldMessengerState messenger,
    String message, {
      required Color color,
      IconData icon = Icons.info_outline_rounded,
    }) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}