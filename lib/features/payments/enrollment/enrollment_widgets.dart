/// enrollment_widgets.dart — UI shared by the single-course and roadmap screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_badges.dart' show appInkOn, appTintOn;
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_depth.dart' show AppExpandCard;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppEase, appMotionOff;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/config/app_config.dart' as helpers;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';

bool isWideLayout(BuildContext context) =>
    MediaQuery.of(context).size.width > 600;

void popToHome(BuildContext context) {
  Navigator.of(context).pushReplacementNamed('/dashboard');
}
// ── Buttons ───────────────────────────────────────────────────────────────────

class SoftOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const SoftOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  /// The kit's secondary button (paper, ink hairline) across the width.
  @override
  Widget build(BuildContext context) =>
      AppButton.secondary(label: label, onPressed: onTap, size: AppButtonSize.lg, expand: true);
}

/// Sticky bottom bar with the main action.
class EnrollConfirmBar extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const EnrollConfirmBar({
    super.key,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  /// The kit's primary button at the phone hero size (56), across the width; busy keeps its width.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.xs, AppSpace.xs),
      child: AppButton.primary(label: label, onPressed: onTap, busy: loading, size: AppButtonSize.lg, expand: true),
    );
  }
}

// ── Fee breakdown ─────────────────────────────────────────────────────────────

class FeeBreakdownCard extends StatefulWidget {
  final FeeQuote? quote; // null while loading
  final String currencySymbol;

  const FeeBreakdownCard({
    super.key,
    required this.quote,
    required this.currencySymbol,
  });

  @override
  State<FeeBreakdownCard> createState() => _FeeBreakdownCardState();
}

class _FeeBreakdownCardState extends State<FeeBreakdownCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = widget.quote;
    final symbol = widget.currencySymbol;
    const tabular = [FontFeature.tabularFigures()];

    // the header: a quiet receipt mark, the editorial title, the total (it glides when the plan or method changes)
    Widget header({required bool loading}) => Row(
          children: [
            Container(
              width: AppIconSize.xl + AppSpace.xxs,
              height: AppIconSize.xl + AppSpace.xxs,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
              child: Icon(Icons.receipt_long_rounded, color: c.primary, size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text('billing_details'.tr, style: AppType.section(context))),
            if (loading)
              const SizedBox(height: AppIconSize.md, child: AppLoadingIndicator(showLogo: false))
            else
              Flexible(
                child: AppCountUp(
                  '${q!.fmt(q.total)} $symbol',
                  memoryKey: 'enroll.total.header',
                  style: AppType.bodyStrong(context).copyWith(color: c.textDark, fontFeatures: tabular),
                ),
              ),
          ],
        );

    if (q == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: header(loading: true),
        ),
      );
    }

    // the kit's expanding card: a 48 px header button with its state, the body opening from where it is
    return AppExpandCard(
      expanded: _expanded,
      onExpandedChanged: (v) => setState(() => _expanded = v),
      header: header(loading: false),
      child: Builder(
        builder: (context) => Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                child: Column(
                  children: [
                    Divider(color: c.divider, height: AppBorder.hairline, thickness: AppBorder.hairline),
                    const SizedBox(height: AppSpace.md),
                    _FeeRow(
                      label: 'course_price'.tr,
                      value: q.fmt(q.coursePrice),
                      icon: Icons.school_rounded,
                    ),
                    if (q.couponDiscount > 0)
                      _FeeRow(
                        key: const ValueKey('enroll.coupon_discount'),
                        label: helpers.AppConfig.lang == 'ar' ? 'خصم القسيمة' : 'Coupon discount',
                        value: '−${q.fmt(q.couponDiscount)}',
                        icon: Icons.local_offer_rounded,
                        sub: q.couponCode,
                      ),
                    _FeeRow(
                      label: 'platform_fees'.tr,
                      value: q.fmt(q.platformFee),
                      icon: Icons.store_rounded,
                    ),
                    _FeeRow(
                      label: 'VAT'.tr,
                      value: q.fmt(q.vatOnPlatform),
                      icon: Icons.receipt_rounded,
                    ),
                    _FeeRow(
                      label: 'gateway_fees'.tr,
                      value: q.fmt(q.gatewayFee),
                      icon: Icons.credit_card_rounded,
                      sub: q.gatewayLabel,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Divider(color: c.divider, height: AppBorder.hairline, thickness: AppBorder.hairline),
                    const SizedBox(height: AppSpace.md),
                    // the total is the page's key figure: large, tabular, in ink (no gradient pill)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: Text('total_label'.tr, style: AppType.section(context))),
                        const SizedBox(width: AppSpace.sm),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: AppCountUp(
                              '${q.fmt(q.total)} $symbol',
                              memoryKey: 'enroll.total',
                              style: AppType.figureLarge(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final String? sub;

  const _FeeRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.body(context)),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: AppType.meta(context)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Text(
            value,
            style: AppType.row(context).copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result screens ────────────────────────────────────────────────────────────

class PaymentVerifyingView extends StatelessWidget {
  const PaymentVerifyingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: AppSpace.xxxl, height: AppSpace.xxxl, child: AppLoadingIndicator()),
            const SizedBox(height: AppSpace.lg),
            Text('verifying_payment_title'.tr, style: AppType.headline(context), textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.xs),
            Text('verifying_payment_subtitle'.tr, style: AppType.body(context), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

enum ResultKind { success, pending, failed }

/// One widget for success / pending / failed (replaces three near-identical screens).
class PaymentResultView extends StatefulWidget {
  final ResultKind kind;
  final String title, message, primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const PaymentResultView({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  State<PaymentResultView> createState() => _PaymentResultViewState();
}

class _PaymentResultViewState extends State<PaymentResultView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;

  /// The mark's side.
  static const double _mark = 112;

  @override
  void initState() {
    super.initState();
    // ONE entrance: the mark settles from 92 % while the page fades in (a strong ease-out, no bounce)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _scale = Tween<double>(begin: 0.92, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: AppEase.out));
    _fade = CurvedAnimation(parent: _ctrl, curve: AppEase.out);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (appMotionOff(context)) _ctrl.value = 1; // Reduce motion: already there
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color tone, IconData icon) = switch (widget.kind) {
      ResultKind.success => (c.success, Icons.check_rounded),
      ResultKind.pending => (c.warning, Icons.hourglass_top_rounded),
      ResultKind.failed => (c.danger, Icons.error_outline_rounded),
    };
    // a tinted disc with a solid core: the outcome in its own colour, no glow
    final tint = appTintOn(context, tone, surface: c.background);

    return FadeTransition(
      opacity: _fade,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Center(
                    child: Container(
                      width: _mark,
                      height: _mark,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                      alignment: Alignment.center,
                      child: Container(
                        width: _mark / 2,
                        height: _mark / 2,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: appInkOn(context, tone, tint)),
                        child: Icon(icon, color: c.onHero, size: AppIconSize.xl),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(widget.title, style: AppType.display(context), textAlign: TextAlign.center),
                const SizedBox(height: AppSpace.sm),
                Text(
                  widget.message,
                  style: AppType.body(context).copyWith(height: 1.8),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.xl),
                AppButton.primary(
                  label: widget.primaryLabel,
                  onPressed: widget.onPrimary,
                  size: AppButtonSize.lg,
                  expand: true,
                ),
                if (widget.secondaryLabel != null &&
                    widget.onSecondary != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  SoftOutlineButton(
                    label: widget.secondaryLabel!,
                    onTap: widget.onSecondary!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy for the three result kinds, shared so both flows say the same thing.
class ResultCopy {
  static String get pendingTitle => 'payment_pending_title'.tr;

  static String get pendingMessage => 'payment_pending_message'.tr;

  // Shown instead of the pair above when the student already has a manual
  // transfer (bank/InstaPay) proof awaiting teacher review for this course —
  // see EnrollmentProvider.pendingIsManualReview.
  static String get pendingReviewTitle => 'payment_pending_review_title'.tr;

  static String get pendingReviewMessage => 'payment_pending_review_message'.tr;

  static String get failedTitle => 'payment_failed_title'.tr;

  static String get failedFallback => 'payment_failed_fallback'.tr;

  // Shown instead of failedTitle when EnrollStep.failed was reached because
  // a teacher rejected a manual transfer — see
  // EnrollmentProvider.manualTransferRejected.
  static String get rejectedTitle => 'payment_rejected_title'.tr;
}

// ── Payment-status badge (course details, next to the enroll button) ───────────

/// Shows the status of a student's outstanding manual-transfer (bank/
/// InstaPay) request for a course, wherever it's dropped in — typically
/// right above the enroll button on the course details screen — so a
/// student with a pending or rejected request sees it before trying to
/// enroll again. Renders nothing when there's no manual-transfer history,
/// or the last one was cancelled/approved (approved implies they're already
/// enrolled, which the normal "isEnrolled" UI already covers).
///
/// Independent of EnrollmentProvider by design: it fetches
/// GET /api/v1/payments/transfer-status itself, so it can be dropped next to
/// the enroll button without that screen needing its own provider wired up
/// for it.
class ManualTransferStatusBanner extends StatefulWidget {
  final String courseId;

  /// Called when the student taps "send payment again" on a rejected
  /// request — normally: reopen the enrollment screen.
  final VoidCallback onRetry;

  const ManualTransferStatusBanner({
    super.key,
    required this.courseId,
    required this.onRetry,
  });

  @override
  State<ManualTransferStatusBanner> createState() =>
      _ManualTransferStatusBannerState();
}

class _ManualTransferStatusBannerState
    extends State<ManualTransferStatusBanner> {
  final _api = ApiClient();
  bool _loading = true;
  String? _status; // "pending" | "approved" | "rejected" | "cancelled" | null
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ManualTransferStatusBanner old) {
    super.didUpdateWidget(old);
    if (old.courseId != widget.courseId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String? status;
    String? reason;
    try {
      final raw = await _api.get(
        '/api/v1/payments/transfer-status?course_id=${widget.courseId}',
      );
      final json = asJsonMap(raw);
      status = json?['status'] as String?;
      reason = json?['rejection_reason'] as String?;
    } catch (_) {
      // No connectivity / unauthenticated / etc. — badge just stays hidden.
      status = null;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _rejectionReason = reason;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading ||
        _status == null ||
        _status == 'cancelled' ||
        _status == 'approved') {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final isRejected = _status == 'rejected';
    final tone = isRejected ? c.danger : context.colors.warning;
    // an opaque tint of the tone with its ink at AA (warning text on its tint needs the darker ink)
    final tint = appTintOn(context, tone);
    final ink = appInkOn(context, tone, tint);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.xs),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: Color.lerp(tint, tone, 0.35)!, width: AppBorder.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
            child: Icon(
              isRejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
              color: ink,
              size: AppIconSize.md,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRejected ? 'transfer_rejected_banner_title'.tr : 'transfer_pending_banner_title'.tr,
                  style: AppType.bodyStrong(context).copyWith(color: ink),
                ),
                if (isRejected && (_rejectionReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(_rejectionReason!, style: AppType.meta(context).copyWith(color: c.textDark)),
                ],
                const SizedBox(height: AppSpace.xxs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton.ghost(
                    label: isRejected ? 'resend_transfer_request'.tr : 'view_request_details'.tr,
                    size: AppButtonSize.sm,
                    onPressed: widget.onRetry,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin scaffold used by both screens so direction + background match.
class EnrollScaffold extends StatelessWidget {
  final Widget child;

  const EnrollScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: BasePage(
        useWebCard: true,
        width: AppWidth.reading,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          // a step swap is a crossfade with a short glide (one object changing, not two queued animations)
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).slow,
            switchInCurve: AppEase.out,
            switchOutCurve: AppEase.out,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(.03, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Re-export so screens can build a ScreenAppBar without another import.
Widget enrollAppBar(String title) => ScreenAppBar(title: title);
