/// teacher_transfers_screen.dart — teacher's "Payment requests" screen:
/// review bank-transfer / InstaPay proofs and accept or reject them, either
/// with the buttons or by dragging the card (accept one way, reject the other).
///
/// Open from the teacher dashboard:
///   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen()));
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityGuardedChip;
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2HeroPage;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

class TeacherTransfersScreen extends StatefulWidget {
  const TeacherTransfersScreen({super.key});

  @override
  State<TeacherTransfersScreen> createState() => _TeacherTransfersScreenState();
}

class _TeacherTransfersScreenState extends State<TeacherTransfersScreen> {
  @override
  void initState() {
    super.initState();
    // Shared singleton provider: loads only if the dashboard hasn't already.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherTransfersProvider>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) => const _TransfersView();
}

class _TransfersView extends StatelessWidget {
  const _TransfersView();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherTransfersProvider>();
    final c = context.colors;

    // Not loaded yet: loader, or error + retry if the first load failed.
    final failedFirstLoad =
        !p.hasLoaded && !p.isLoading && p.errorMessage != null;
    final currencies = {for (final x in p.items) x.currency};
    final total = p.items.fold<double>(0, (a, x) => a + x.amount);

    return Directionality(
      textDirection: Helpers.pageDirection,
      // T1 (Tea1Home?screen=transfers): the teacher hero with the two counts, the requests ride up over it
      child: T2HeroPage(
        pageKey: const ValueKey('transfer_requests'),
        title: 'transfer_requests_title'.tr,
        onRefresh: p.load,
        width: AppWidth.content,
        hero: AppHero(
          title: 'transfer_requests_title'.tr,
          subtitle: 't1_hm_transfers_sub'.tr,
          stats: [
            if (p.hasLoaded) AppHeroStat(value: '${p.items.length}', label: 't1_hm_tr_waiting'.tr),
            if (p.hasLoaded && p.items.isNotEmpty && currencies.length == 1)
              AppHeroStat(value: '${total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 2)} ${currencies.first}', label: 't1_hm_tr_total'.tr),
          ],
        ),
        children: [
          if (!p.hasLoaded && !failedFirstLoad)
            const AppListSkeleton(padding: EdgeInsets.zero)
          else if (failedFirstLoad)
            RequestStateView(
              icon: Icons.error_outline_rounded,
              color: c.danger,
              message: p.errorMessage ?? 'failed_to_load'.tr,
              actionLabel: 'retry'.tr,
              onAction: p.load,
            )
          else if (p.items.isEmpty)
            RequestStateView(icon: Icons.task_alt_rounded, message: 'no_pending_requests'.tr)
          else ...[
            SwipeHintBanner(key: const ValueKey('transfer_requests.hint'), count: p.items.length),
            for (var i = 0; i < p.items.length; i++)
              // The screen's one entrance: the first requests settle in once per visit.
              AppReveal(
                key: ValueKey(p.items[i].paymentId),
                index: i,
                group: 'transfers',
                child: _TransferCard(transfer: p.items[i]),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final PendingTransfer transfer;

  const _TransferCard({required this.transfer});

  static List<String> get _quickReasons => [
    'transfer_reason_unclear_receipt'.tr,
    'transfer_reason_amount_mismatch'.tr,
    'transfer_reason_invalid_details'.tr,
  ];

  Future<bool> _approve(BuildContext context) async {
    final p = context.read<TeacherTransfersProvider>();

    final ok = await p.approve(transfer.paymentId);
    showRequestSnack(
      ok
          ? 'request_approved'.tr
          : (p.errorMessage ?? 'request_approve_failed'.tr),
      error: !ok,
      icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  Future<bool> _reject(BuildContext context) async {
    final p = context.read<TeacherTransfersProvider>();

    final reason = await showAppSheet<String>(
      context,
      (_) => TransferRejectBody(
        studentName: transfer.studentName,
        title: 'rejection_reason_title'.tr,
        hint: 'rejection_reason_hint'.tr,
        quickReasons: _quickReasons,
      ),
    );
    if (reason == null || reason.isEmpty) {
      return false; // cancelled → spring back
    }

    final ok = await p.reject(transfer.paymentId, reason);
    showRequestSnack(
      ok
          ? 'request_rejected'.tr
          : (p.errorMessage ?? 'request_reject_failed'.tr),
      error: true, // a rejection reads as red, as before
      icon: ok ? Icons.cancel_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  void _openImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.colors.heroShade,
        insetPadding: const EdgeInsets.all(AppSpace.sm),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet))),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.network(
                  transfer.proofImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: context.colors.onHeroMuted,
                      size: AppIconSize.hero,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpace.xs,
              right: AppSpace.xs,
              child: IconButton(tooltip: t('إغلاق', 'Close'), 
                onPressed: () => Navigator.pop(ctx),
                icon: Icon(Icons.close_rounded, color: context.colors.onHero),
                style: IconButton.styleFrom(backgroundColor: context.colors.heroGlass),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SwipeRequestCard(
      itemId: transfer.paymentId,
      onApprove: () => _approve(context),
      onReject: () => _reject(context),
      onRemoved: () => context.read<TeacherTransfersProvider>().removeItem(
        transfer.paymentId,
      ),
      builder: (context, ctl) => RequestCardShell(
        busy: ctl.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: student, course, amount ──
            Row(
              children: [
                RequestAvatar(name: transfer.studentName),
                AppSpace.gapSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // D-290: a teacher and an admin both read this queue, so the server says per mention
                      // whether the record opens (POST /entities/access, one request for the whole list).
                      EntityGuardedChip(
                        EntityRef(EntityKind.student, transfer.studentId, label: transfer.studentName),
                        maxWidth: 160,
                      ),
                      EntityGuardedChip(
                        EntityRef(EntityKind.course, transfer.courseId, label: transfer.courseName),
                        maxWidth: 160,
                      ),
                    ],
                  ),
                ),
                AppSpace.gapXs,
                Flexible(child: _AmountPill(
                  amount: transfer.amount,
                  currency: transfer.currency,
                )),
              ],
            ),
            AppSpace.gapMd,

            // ── Transfer details: a quiet input-tone well on the paper card (tone, not a tinted wash) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: AppRadius.controlAll,
                border: Border.all(color: c.divider, width: AppBorder.hairline),
              ),
              child: Column(
                children: [
                  RequestInfoRow(
                    icon: transfer.isBankTransfer
                        ? Icons.account_balance_rounded
                        : Icons.bolt_rounded,
                    label: 'payment_method_title'.tr,
                    value: transfer.isBankTransfer
                        ? 'transfer_bank_title'.tr
                        : 'transfer_instapay_title'.tr,
                  ),
                  if (transfer.plan != null) ...[
                    AppSpace.gapXs,
                    RequestInfoRow(
                      icon: Icons.event_available_rounded,
                      label: 'plan_label'.tr,
                      value: PlanKeys.titleKey(transfer.plan!).tr,
                    ),
                  ],
                  if (transfer.coursePrice != null) ...[
                    AppSpace.gapXs,
                    RequestInfoRow(
                      icon: Icons.sell_outlined,
                      label: 'transfer_course_price'.tr,
                      value:
                          '${transfer.coursePrice!.toStringAsFixed(2)} ${transfer.currency}',
                    ),
                  ],
                  if (transfer.fees != null) ...[
                    AppSpace.gapXs,
                    RequestInfoRow(
                      icon: Icons.receipt_long_outlined,
                      label: 'transfer_fees_total'.tr,
                      value:
                          '${(transfer.fees!.platformFee + transfer.fees!.vatOnPlatform + transfer.fees!.gatewayFee).toStringAsFixed(2)} ${transfer.currency}',
                    ),
                  ],
                  AppSpace.gapXs,
                  RequestInfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'sender_name_label'.tr,
                    value: transfer.senderName,
                  ),
                  if (transfer.senderPhone?.isNotEmpty ?? false) ...[
                    AppSpace.gapXs,
                    RequestInfoRow(
                      icon: Icons.phone_outlined,
                      label: 'sender_phone_short'.tr,
                      value: transfer.senderPhone!,
                      copyable: true,
                    ),
                  ],
                  if (transfer.transferReference?.isNotEmpty ?? false) ...[
                    AppSpace.gapXs,
                    RequestInfoRow(
                      icon: Icons.tag_rounded,
                      label: 'reference_number'.tr,
                      value: transfer.transferReference!,
                      copyable: true,
                    ),
                  ],
                ],
              ),
            ),
            AppSpace.gapSm,

            // ── Proof image ──
            _ProofImage(
              key: const ValueKey('transfer_requests.proof_image'),
              url: transfer.proofImageUrl,
              onTap: () => _openImage(context),
            ),
            AppSpace.gapMd,

            RequestActionButtons(
              key: const ValueKey('transfer_requests.actions'),
              ctl: ctl,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountPill extends StatelessWidget {
  const _AmountPill({required this.amount, required this.currency});

  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          borderRadius: AppRadius.controlAll,
          color: c.blockSky,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${amount.toStringAsFixed(2)} $currency',
            maxLines: 1,
            style: AppType.figure(context).copyWith(color: c.blockInk),
          ),
        ),
      ),
    );
  }
}

class _ProofImage extends StatelessWidget {
  const _ProofImage({super.key, required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  static const double _height = 170;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.controlAll,
        child: Stack(
          children: [
            Image.network(
              url,
              height: _height,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      height: _height,
                      alignment: Alignment.center,
                      color: c.divider.withValues(alpha: 0.4),
                      child: const SizedBox(
                        width: AppIconSize.lg,
                        height: AppIconSize.lg,
                        child: AppLoadingIndicator(showLogo: false),
                      ),
                    ),
              errorBuilder: (_, _, _) => Container(
                height: _height,
                alignment: Alignment.center,
                color: c.divider.withValues(alpha: 0.4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: c.textLight,
                      size: AppIconSize.xl,
                    ),
                    const SizedBox(height: AppSpace.xxs),
                    Text('receipt_load_failed'.tr, style: c.caption),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: AppSpace.xs,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [c.heroShade.withValues(alpha: 0.7), c.heroShade.withValues(alpha: 0)],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.zoom_out_map_rounded,
                      color: c.onHero,
                      size: AppIconSize.sm,
                    ),
                    const SizedBox(width: AppSpace.xxs),
                    Flexible(
                      child: Text(
                        'receipt_tap_to_zoom'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(color: c.onHero),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The reject sheet (Tea1Home?screen=reject): who is being turned down, the quick reasons as chips, the reason field
/// (a reason is always asked for: Reject stays off while it is empty). Pops the reason, or null on Cancel. Plain
/// values, so the layout harness and the renders draw it as it is.
class TransferRejectBody extends StatefulWidget {
  const TransferRejectBody({super.key, required this.title, required this.hint, required this.quickReasons, this.studentName});

  final String title, hint;
  final List<String> quickReasons;
  final String? studentName;

  @override
  State<TransferRejectBody> createState() => _TransferRejectBodyState();
}

class _TransferRejectBodyState extends State<TransferRejectBody> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final valid = _ctrl.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: appTintOn(context, c.danger), borderRadius: AppRadius.controlAll),
            child: Icon(Icons.close_rounded, color: appInkOn(context, c.danger, appTintOn(context, c.danger)), size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(widget.title, style: AppType.headline(context))),
              if ((widget.studentName ?? '').isNotEmpty)
                Text(widget.studentName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final r in widget.quickReasons)
            AppChoiceChip(label: r, selected: _ctrl.text == r, onTap: () => setState(() => _ctrl.text = r)),
        ]),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _ctrl,
          minLines: 3,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context, hint: widget.hint),
        ),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(child: AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: AppButton.danger(
              key: const ValueKey('transfer_requests.reject_confirm'),
              label: 'reject'.tr,
              onPressed: valid ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
            ),
          ),
        ]),
      ]),
    );
  }
}
