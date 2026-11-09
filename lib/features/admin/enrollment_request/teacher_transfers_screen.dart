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
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/utils/helpers.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../student/enrollment/enrollment_models.dart';
import 'teacher_transfers_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import '../admin_common.dart' show t;

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

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        key: const ValueKey('transfer_requests'),
        useWebCard: true,
        width: AppWidth.wide,
        appBar: ScreenAppBar(title: 'transfer_requests_title'.tr),
        child: !p.hasLoaded && !failedFirstLoad
            ? const AppListSkeleton()
            : AppRefresh(
                onRefresh: p.load,
                child: failedFirstLoad
                    ? RequestStateView(
                        icon: Icons.error_outline_rounded,
                        color: c.danger,
                        message: p.errorMessage ?? 'failed_to_load'.tr,
                        actionLabel: 'retry'.tr,
                        onAction: p.load,
                      )
                    : p.items.isEmpty
                    ? RequestStateView(
                        icon: Icons.task_alt_rounded,
                        message: 'no_pending_requests'.tr,
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        // +1: the hint banner is the first row.
                        itemCount: p.items.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return SwipeHintBanner(
                              key: const ValueKey('transfer_requests.hint'),
                              count: p.items.length,
                            );
                          }
                          final t = p.items[i - 1];
                          return _TransferCard(
                            key: ValueKey(t.paymentId),
                            transfer: t,
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final PendingTransfer transfer;

  const _TransferCard({super.key, required this.transfer});

  static List<String> get _quickReasons => [
    'transfer_reason_unclear_receipt'.tr,
    'transfer_reason_amount_mismatch'.tr,
    'transfer_reason_invalid_details'.tr,
  ];

  Future<bool> _approve(BuildContext context) async {
    final p = context.read<TeacherTransfersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final c = context.colors;

    final ok = await p.approve(transfer.paymentId);
    showRequestSnack(
      messenger,
      ok
          ? 'request_approved'.tr
          : (p.errorMessage ?? 'request_approve_failed'.tr),
      color: ok ? c.success : c.danger,
      icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  Future<bool> _reject(BuildContext context) async {
    final p = context.read<TeacherTransfersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final c = context.colors;

    final reason = await showReasonDialog(
      context,
      title: 'rejection_reason_title'.tr,
      hint: 'rejection_reason_hint'.tr,
      requireReason: true,
      quickReasons: _quickReasons,
    );
    if (reason == null || reason.isEmpty) {
      return false; // cancelled → spring back
    }

    final ok = await p.reject(transfer.paymentId, reason);
    showRequestSnack(
      messenger,
      ok
          ? 'request_rejected'.tr
          : (p.errorMessage ?? 'request_reject_failed'.tr),
      color: c.danger,
      icon: ok ? Icons.cancel_rounded : Icons.error_outline_rounded,
    );
    return ok;
  }

  void _openImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.colors.heroShade,
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // D-290: a teacher and an admin both read this queue, so the server says per mention
                      // whether the record opens (POST /entities/access, one request for the whole list).
                      EntityGuardedChip(
                        EntityRef(EntityKind.student, transfer.studentId, label: transfer.studentName),
                        maxWidth: 320,
                      ),
                      EntityGuardedChip(
                        EntityRef(EntityKind.course, transfer.courseId, label: transfer.courseName),
                        maxWidth: 320,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _AmountPill(
                  amount: transfer.amount,
                  currency: transfer.currency,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Transfer details ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.primary.withValues(alpha: 0.12)),
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
                    const SizedBox(height: 10),
                    RequestInfoRow(
                      icon: Icons.event_available_rounded,
                      label: 'plan_label'.tr,
                      value: PlanKeys.titleKey(transfer.plan!).tr,
                    ),
                  ],
                  if (transfer.coursePrice != null) ...[
                    const SizedBox(height: 10),
                    RequestInfoRow(
                      icon: Icons.sell_outlined,
                      label: 'transfer_course_price'.tr,
                      value:
                          '${transfer.coursePrice!.toStringAsFixed(2)} ${transfer.currency}',
                    ),
                  ],
                  if (transfer.fees != null) ...[
                    const SizedBox(height: 10),
                    RequestInfoRow(
                      icon: Icons.receipt_long_outlined,
                      label: 'transfer_fees_total'.tr,
                      value:
                          '${(transfer.fees!.platformFee + transfer.fees!.vatOnPlatform + transfer.fees!.gatewayFee).toStringAsFixed(2)} ${transfer.currency}',
                    ),
                  ],
                  const SizedBox(height: 10),
                  RequestInfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'sender_name_label'.tr,
                    value: transfer.senderName,
                  ),
                  if (transfer.senderPhone?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 10),
                    RequestInfoRow(
                      icon: Icons.phone_outlined,
                      label: 'sender_phone_short'.tr,
                      value: transfer.senderPhone!,
                      copyable: true,
                    ),
                  ],
                  if (transfer.transferReference?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 10),
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
            const SizedBox(height: 12),

            // ── Proof image ──
            _ProofImage(
              key: const ValueKey('transfer_requests.proof_image'),
              url: transfer.proofImageUrl,
              onTap: () => _openImage(context),
            ),
            const SizedBox(height: 14),

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: c.primary.withValues(alpha: 0.10),
        border: Border.all(color: c.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        '${amount.toStringAsFixed(2)} $currency',
        style: c.h3.copyWith(
          fontSize: 14,
          color: c.primary,
          fontWeight: FontWeight.w800,
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
        borderRadius: BorderRadius.circular(14),
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
                        width: 26,
                        height: 26,
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
                      size: 34,
                    ),
                    const SizedBox(height: 6),
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
                  horizontal: 12,
                  vertical: 10,
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
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'receipt_tap_to_zoom'.tr,
                      style: TextStyle(
                        color: c.onHero,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
