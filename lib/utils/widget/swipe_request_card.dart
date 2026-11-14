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
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

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
        tint: c.successTint,
        icon: Icons.check_circle_rounded,
        label: widget.approveLabel ?? 'request_accept'.tr,
        alignment: AlignmentDirectional.centerStart,
      ),
      secondaryBackground: _SwipeBackground(
        color: c.danger,
        tint: c.dangerTint,
        icon: Icons.cancel_rounded,
        label: widget.rejectLabel ?? 'request_reject'.tr,
        alignment: AlignmentDirectional.centerEnd,
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
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
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

/// What a drag reveals under the card: the decision's own tint (success / danger) with its mark and word in ink
/// that reads on it, never a gradient.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.tint,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color tint;
  final IconData icon;
  final String label;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final ink = appInkOn(context, color, tint);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Container(
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: ink, size: AppIconSize.xl),
              const SizedBox(height: AppSpace.xxs),
              Text(label, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card pieces
// ─────────────────────────────────────────────────────────────────────────────

/// The card surface: paper on a warm hairline (no resting shadow), a thin solid accent line on top.
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
      duration: AppMotion.of(context).base,
      opacity: busy ? 0.65 : 1,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: accent, child: const SizedBox(height: AppBorder.focus)),
            Padding(padding: AppSpace.card, child: child),
          ],
        ),
      ),
    );
  }
}

/// A round mark with the first letter of the name, on the person's own block tone (stable per name).
class RequestAvatar extends StatelessWidget {
  const RequestAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first);
    final block = AppBlockColors.of(context, AppBlockTone.forKey('person-$trimmed'));
    return Container(
      width: AppTouch.min,
      height: AppTouch.min,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: block.surface),
      child: Text(
        initial,
        style: AppType.section(context).copyWith(color: block.ink, height: 1),
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

  /// The icon well's side.
  static const double _well = AppIconSize.xl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Row(
      children: [
        Container(
          width: _well,
          height: _well,
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(icon, size: AppIconSize.sm, color: c.textMedium),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppType.meta(context)),
              Text(value, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
            ],
          ),
        ),
        if (copyable) Icon(Icons.copy_rounded, size: AppIconSize.sm, color: c.textLight),
      ],
    );

    if (!copyable) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        showAppNotice('copied_to_clipboard'.tr);
      },
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: row),
    );
  }
}

/// Reject (danger outline) + Approve (the solid primary) wired to the swipe flow.
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
    return Row(
      children: [
        Expanded(
          child: AppButton.danger(
            dangerOutline: true,
            expand: true,
            onPressed: ctl.busy ? null : ctl.reject,
            icon: Icons.close_rounded,
            label: rejectLabel ?? 'request_reject'.tr,
          ),
        ),
        AppSpace.gapSm,
        Expanded(
          child: AppButton.primary(
            expand: true,
            busy: ctl.busy,
            onPressed: ctl.approve,
            icon: Icons.check_rounded,
            label: approveLabel ?? 'request_accept'.tr,
          ),
        ),
      ],
    );
  }
}

/// List header: pending count + which way to drag, on the sky (information) block. The sides are computed from the
/// current text direction, so the wording is right in RTL and LTR.
class SwipeHintBanner extends StatelessWidget {
  const SwipeHintBanner({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Approve = drag from start towards end (physically left in RTL).
    final hint = rtl ? 'swipe_hint_accept_left'.tr : 'swipe_hint_accept_right'.tr;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppBlock(
        tone: AppBlockTone.sky,
        padding: AppSpace.card,
        child: Builder(builder: (context) {
          final ink = AppBlock.colorsOf(context);
          return Row(
            children: [
              Icon(Icons.swipe_rounded, color: ink.ink, size: AppIconSize.lg),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${'requests_pending_review'.tr}',
                      style: AppType.bodyStrong(context).copyWith(color: ink.ink),
                    ),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(hint, style: AppType.meta(context).copyWith(color: ink.muted)),
                  ],
                ),
              ),
            ],
          );
        }),
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

  /// Kept for existing callers: the drawn plate carries the state (the danger colour reads as an error state).
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final error = color != null && color == context.colors.danger;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xxl),
      children: [
        AppEmpty(
          icon: icon,
          title: message,
          actionLabel: actionLabel,
          onAction: onAction,
          tone: error ? AppBlockTone.paper : AppBlockTone.peach,
        ),
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
    barrierColor: appScrimColor(context),
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
      backgroundColor: c.cardBg,
      surfaceTintColor: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      title: Row(
        children: [
          Icon(Icons.report_gmailerrorred_rounded, color: c.danger, size: AppIconSize.lg),
          AppSpace.gapSm,
          Expanded(child: Text(widget.title, style: AppType.pageTitle(context))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.quickReasons.isNotEmpty) ...[
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final q in widget.quickReasons)
                    AppChoiceChip(
                      label: q,
                      selected: _ctrl.text.trim() == q,
                      onTap: () {
                        _ctrl.text = q;
                        _ctrl.selection = TextSelection.collapsed(
                          offset: q.length,
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
              AppSpace.gapSm,
            ],
            TextField(
              controller: _ctrl,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              style: appFieldTextStyle(context),
              decoration: appFieldDecoration(context, hint: widget.hint),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.ghost(
          onPressed: () => Navigator.pop(context),
          label: 'cancel'.tr,
        ),
        AppButton.danger(
          onPressed: _valid
              ? () => Navigator.pop(context, _ctrl.text.trim())
              : null,
          label: 'request_reject'.tr,
        ),
      ],
    );
  }
}

/// The result toast (the kit's notice, drawn above every sheet and dialog). [icon] is kept for existing callers.
void showRequestSnack(
    String message, {
      required bool error,
      IconData icon = Icons.info_outline_rounded,
    }) {
  showAppNotice(message, error: error);
}
