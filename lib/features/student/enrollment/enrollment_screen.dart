/// enrollment_screen.dart — single-course enrollment / payment.
///
/// Works on Flutter Mobile (full screen) and Web (centred, max 560 px).
/// STC Pay and bank transfer are gone; what's left is saved cards (Moyasar),
/// a new card, and free enrollment.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/student/enrollment/saved_cards/saved_payment_models.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../shared/profile/course_instractor_profile.dart';
import '../../student/models.dart';
import 'enrollment_models.dart';
import 'enrollment_provider.dart';
import 'enrollment_widgets.dart';

const _kMadaColor = Color(0xFF0D47A1);
const _kVisaColor = Color(0xFF1A237E);
const _kMcColor = Color(0xFFB71C1C);
const _kNewCardColor = Color(0xFF0F4C81);

class EnrollmentScreen extends StatelessWidget {
  final CourseModel course;

  const EnrollmentScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Created here (not in a State above it) so the provider is in scope
        // for everything below; the load starts after the first frame.
        ChangeNotifierProvider(
          create: (_) => EnrollmentProvider(course)..scheduleInitialLoad(),
        ),
      ],
      child: const _EnrollView(),
    );
  }
}

// ── Step switcher ─────────────────────────────────────────────────────────────

class _EnrollView extends StatelessWidget {
  const _EnrollView();

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();

    return EnrollScaffold(
      child: enroll.isLoading
          ? Center(child: AppLoadingIndicator())
          : switch (enroll.step) {
              EnrollStep.method => const _MethodStep(key: ValueKey('method')),
              EnrollStep.verifying => const PaymentVerifyingView(
                key: ValueKey('verifying'),
              ),
              EnrollStep.pending => PaymentResultView(
                key: const ValueKey('pending'),
                kind: ResultKind.pending,
                title: enroll.pendingIsManualReview
                    ? ResultCopy.pendingReviewTitle
                    : ResultCopy.pendingTitle,
                message: enroll.pendingIsManualReview
                    ? ResultCopy.pendingReviewMessage
                    : ResultCopy.pendingMessage,
                primaryLabel: 'back_to_home'.tr,
                onPrimary: () => popToHome(context),
                // Manual-transfer review only: let the student withdraw the
                // pending proof and go send a corrected one right away, instead
                // of waiting for the teacher to reject it first.
                secondaryLabel: enroll.pendingIsManualReview
                    ? 'resend_transfer_request'.tr
                    : null,
                // The old proof is withdrawn when the new one is submitted
                // (TransferPaymentProvider.submit), so just go back to the picker.
                onSecondary: () async {
                  await enroll.prepareMethodStep();
                  enroll.setStep(EnrollStep.method);
                },
              ),
              EnrollStep.success => PaymentResultView(
                key: const ValueKey('success'),
                kind: ResultKind.success,
                title: 'enroll_success_title'.tr,
                message: 'enroll_success_message'.tr,
                primaryLabel: 'start_learning_now'.tr,
                onPrimary: () => popToHome(context),
              ),
              EnrollStep.failed => PaymentResultView(
                key: const ValueKey('failed'),
                kind: ResultKind.failed,
                title: enroll.manualTransferRejected
                    ? ResultCopy.rejectedTitle
                    : ResultCopy.failedTitle,
                message: enroll.failureReason ?? ResultCopy.failedFallback,
                primaryLabel: enroll.manualTransferRejected
                    ? 'resend_transfer_request'.tr
                    : 'try_again_payment'.tr,
                onPrimary: enroll.backToMethod,
                secondaryLabel: 'back_to_home'.tr,
                onSecondary: () => popToHome(context),
              ),
            },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Method step
// ═════════════════════════════════════════════════════════════════════════════

class _MethodStep extends StatelessWidget {
  const _MethodStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final quote = enroll.quote;

    final label = enroll.isFree
        ? 'enroll_free_now'.tr
        : quote == null
        ? 'continue'.tr
        : '${'pay_action'.tr} ${quote.fmt(quote.total)} ${enroll.currencySymbol}';

    return Center(
      child: Column(
        children: [
          enrollAppBar(
            enroll.isFree
                ? 'enroll_course_title'.tr
                : 'complete_payment_title'.tr,
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CourseSummaryCard(
                    course: enroll.course,
                    currencySymbol: enroll.currencySymbol,
                    price: enroll.selectedOption?.finalPrice,
                  ),
                  const SizedBox(height: 24),
                  if (!enroll.optionsLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: AppLoadingIndicator(),
                      ),
                    )
                  else if (enroll.isFree)
                    const _FreeCourseBanner()
                  else ...[
                    const _PricePlanPicker(),
                    const SizedBox(height: 20),
                    const _PaymentMethodPicker(),
                    const SizedBox(height: 20),
                    FeeBreakdownCard(
                      quote: quote,
                      currencySymbol: enroll.currencySymbol,
                    ),
                  ],
                ],
              ),
            ),
          ),
          EnrollConfirmBar(
            label: label,
            loading: enroll.isLoading,
            onTap: enroll.canConfirm ? () => enroll.confirm(context) : null,
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

String _fmtMoney(double v, String symbol) =>
    '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)} $symbol';

/// Gradient icon chip + title used by every section on this screen.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.primary, c.primary.withValues(alpha: .7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: .25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text(title, style: c.h3.copyWith(fontSize: 15)),
      ],
    );
  }
}

// ── Course summary ────────────────────────────────────────────────────────────

class _CourseSummaryCard extends StatelessWidget {
  final CourseModel course;
  final String currencySymbol;

  /// Price of the plan the student picked (falls back to the course's own).
  final double? price;

  const _CourseSummaryCard({
    required this.course,
    required this.currencySymbol,
    this.price,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary.withValues(alpha: .09), c.cardBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.primary.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: .10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AppNetworkImage(
                url: course.imageUrl,
                width: 92,
                height: 92,
                heroTag: 'course-enrollment-${course.id}',
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ??
                      '',
                  style: c.h3.copyWith(fontSize: 16, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (course.teacher != null) ...[
                  const SizedBox(height: 6),
                  InstructorAvatar(
                    teacher: course.teacher!,
                    size: 50,
                    canOpen: true,
                    showTitle: true,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PriceBadge(
                      price: price ?? course.finalPrice ?? 0,
                      currencySymbol: currencySymbol,
                    ),
                    _TypeTag(type: course.type),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final double price;
  final String currencySymbol;

  const _PriceBadge({required this.price, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFree = price == 0;
    final tone = isFree ? c.success : c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone.withValues(alpha: .15), tone.withValues(alpha: .06)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: .3)),
      ),
      child: Text(
        isFree ? 'free'.tr : '${price.toStringAsFixed(2)} $currencySymbol',
        style: c.label.copyWith(
          color: tone,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String type;

  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLive = type == 'live';
    final tone = isLive ? c.danger : c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? 'type_tag_live'.tr : 'type_tag_recorded'.tr,
        style: c.caption.copyWith(
          color: tone,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FreeCourseBanner extends StatelessWidget {
  const _FreeCourseBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.success.withValues(alpha: .10),
            c.success.withValues(alpha: .04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.success.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.success.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.card_giftcard_rounded,
              color: c.success,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'free_course_banner_title'.tr,
                  style: c.h3.copyWith(color: c.success),
                ),
                const SizedBox(height: 4),
                Text('free_banner_subtitle'.tr, style: c.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Price plan picker ─────────────────────────────────────────────────────────

/// Every plan the course sells (monthly / 6 months / yearly) — pick one.
/// Each plan card shows the monthly cost AND the total for the whole plan.
class _PricePlanPicker extends StatelessWidget {
  const _PricePlanPicker();

  /// "Save x%" vs. paying the monthly plan for the same number of months.
  static int? _savePercent(List<PriceOption> all, PriceOption o) {
    final monthly = all.where((e) => e.plan == PlanKeys.monthly).firstOrNull;
    if (monthly == null ||
        o.plan == PlanKeys.monthly ||
        monthly.finalPrice <= 0) {
      return null;
    }
    final full = monthly.finalPrice * PlanKeys.months(o.plan);
    final pct = ((1 - o.finalPrice / full) * 100).round();
    return pct > 0 ? pct : null;
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final options = enroll.priceOptions;

    // The plan with the biggest saving gets the "Best value" ribbon.
    String? bestPlan;
    var bestPct = 0;
    for (final o in options) {
      final pct = _savePercent(options, o) ?? 0;
      if (pct > bestPct) {
        bestPct = pct;
        bestPlan = o.plan;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.event_available_rounded,
          title: 'choose_plan_title'.tr,
        ),
        const SizedBox(height: 14),
        if (options.length == 1)
          _PlanTile(
            option: options[0],
            selected: enroll.selectedPlan == options[0].plan,
            currencySymbol: enroll.currencySymbol,
            savePercent: _savePercent(options, options[0]),
            isBestValue: options[0].plan == bestPlan,
            onTap: () => enroll.selectPlan(options[0].plan),
          )
        else
          Row(
            children: [
              for (final o in options)
                Expanded(
                  child: _PlanTile(
                    option: o,
                    selected: enroll.selectedPlan == o.plan,
                    currencySymbol: enroll.currencySymbol,
                    savePercent: _savePercent(options, o),
                    isBestValue: o.plan == bestPlan,
                    onTap: () => enroll.selectPlan(o.plan),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final PriceOption option;
  final bool selected;
  final bool isBestValue;
  final String currencySymbol;
  final int? savePercent;
  final VoidCallback onTap;

  const _PlanTile({
    required this.option,
    required this.selected,
    required this.isBestValue,
    required this.currencySymbol,
    required this.savePercent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final m = PlanKeys.months(option.plan);
    final months = m <= 0 ? 1 : m;
    final perMonth = option.finalPrice / months;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        constraints: BoxConstraints(minHeight: 200, maxWidth: 200),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    c.primary.withValues(alpha: .10),
                    c.primary.withValues(alpha: .03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.primary : c.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.primary.withValues(alpha: .20),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Row(
              children: [
                _RadioDot(selected: selected),
                Spacer(),
                if (isBestValue)
                  _PlanBadge(
                    label: 'plan_best_value'.tr,
                    icon: Icons.workspace_premium_rounded,
                    tone: Colors.amber.shade800,
                    filled: true,
                  )
                else if (savePercent != null)
                  _PlanBadge(
                    label: '${'plan_save'.tr} $savePercent%',
                    tone: c.success,
                  ),
              ],
            ),
            // ── Title row ────────────────────────────────────────────────
            Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PlanKeys.titleKey(option.plan).tr,
                        style: c.label.copyWith(
                          color: selected ? c.primary : c.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        PlanKeys.accessKey(option.plan).tr,
                        style: c.caption.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // ── Monthly cost (hero number) ───────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _fmtMoney(perMonth, currencySymbol),
                      style: c.h3.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'bahji',
                        color: selected ? c.primary : c.textDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'plan_per_month'.tr,
                    style: c.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // ── Total for the whole plan ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? c.primary.withValues(alpha: .08)
                    : c.divider.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
              ),

              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 15,
                        color: selected
                            ? c.primary
                            : c.textDark.withValues(alpha: .6),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'plan_total'.tr,
                        style: c.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (option.hasDiscount) ...[
                        Text(
                          _fmtMoney(option.price, currencySymbol),
                          style: c.caption.copyWith(
                            fontSize: 11,
                            fontFamily: 'bahji',
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _fmtMoney(option.finalPrice, currencySymbol),
                        style: c.label.copyWith(
                          fontFamily: 'bahji',

                          color: selected ? c.primary : c.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
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

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.primary : Colors.transparent,
        border: Border.all(color: selected ? c.primary : c.divider, width: 2),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _PlanBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color tone;
  final bool filled;

  const _PlanBadge({
    required this.label,
    required this.tone,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: filled ? .16 : .12),
        borderRadius: BorderRadius.circular(8),
        border: filled ? Border.all(color: tone.withValues(alpha: .35)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: c.caption.copyWith(
              color: tone,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
// ── Payment method picker ─────────────────────────────────────────────────────

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker();

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final g = enroll.gateway;
    // "New card" is selected only when neither a saved card nor a transfer method is.
    final newCardSelected =
        enroll.selectedCard == null && enroll.selectedManualMethod == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.payment_rounded, title: 'payment_method'.tr),
        const SizedBox(height: 14),
        if (g == null || !g.anyMethodEnabled)
          _NoMethodsNotice(onRetry: enroll.prepareMethodStep)
        else ...[
          // Saved cards exactly as the backend returned them (only while card payments are open).
          for (final card in enroll.availableSavedCards)
            _MethodTile(
              selected: enroll.selectedCard?.id == card.id,
              icon: Icons.credit_card_rounded,
              iconColor: _brandColor(card.cardBrand?.apiKey),
              title: card.displayTitle,
              // Expiry, not CardBrand.feeLabel: that label is a hard-coded rate that drifts from the
              // admin-managed fees. The real fee of the selected card is in the server-quoted breakdown below.
              subtitle: card.displaySubtitle,
              badge: card.isDefault ? 'default_card_badge'.tr : null,
              onTap: () => enroll.selectSavedCard(card),
            ),
          if (g.cardEnabled)
            _MethodTile(
              selected: newCardSelected,
              icon: Icons.add_card_rounded,
              iconColor: _kNewCardColor,
              title: 'new_card_title'.tr,
              subtitle: 'new_card_subtitle'.tr,
              customBadge: const _SecureBadge(),
              onTap: enroll.selectNewCard,
            ),
          if (g.bankTransferEnabled)
            _MethodTile(
              selected: enroll.selectedManualMethod == 'bank_transfer',
              icon: Icons.account_balance_rounded,
              iconColor: const Color(0xFF2E7D32),
              title: g.labelFor('bank_transfer') ?? 'transfer_bank_title'.tr,
              subtitle: 'bank_transfer_subtitle'.tr,
              onTap: () => enroll.selectManualMethod('bank_transfer'),
            ),
          if (g.instapayEnabled)
            _MethodTile(
              selected: enroll.selectedManualMethod == 'instapay',
              icon: Icons.qr_code_2_rounded,
              iconColor: const Color(0xFF6A1B9A),
              title: g.labelFor('instapay') ?? 'transfer_instapay_title'.tr,
              subtitle: 'instapay_subtitle'.tr,
              onTap: () => enroll.selectManualMethod('instapay'),
            ),
        ],
      ],
    );
  }
}

/// Tile colour per card network (falls back to the "new card" blue).
Color _brandColor(String? apiKey) => switch (apiKey?.toLowerCase()) {
  'mada' => const Color(0xFF0B8A4F),
  'visa' => const Color(0xFF1A1F71),
  'mastercard' || 'master' => const Color(0xFFEB001B),
  'amex' || 'american_express' => const Color(0xFF2E77BB),
  _ => _kNewCardColor,
};

/// Shown when the admin has closed every method (or the config could not be loaded).
class _NoMethodsNotice extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _NoMethodsNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.payments_outlined, size: 30, color: c.textLight),
          const SizedBox(height: 10),
          Text(
            'payment_no_methods_available'.tr,
            style: c.body.copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          TextButton(onPressed: onRetry, child: Text('retry'.tr)),
        ],
      ),
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_rounded, size: 9, color: Colors.green),
        const SizedBox(width: 3),
        Text(
          'secure_badge'.tr,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.green.shade700,
            fontFamily: 'bahji',
          ),
        ),
      ],
    ),
  );
}

class _MethodTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final String? badge;
  final Widget? customBadge;
  final VoidCallback onTap;

  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.customBadge,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: .05) : c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c.primary : c.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.primary.withValues(alpha: .14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : c.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: selected ? .18 : .09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: c.label.copyWith(
                            color: selected ? c.primary : c.textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: c.caption.copyWith(
                              color: Colors.amber.shade800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                      if (customBadge != null) ...[
                        const SizedBox(width: 6),
                        customBadge!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: c.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? c.primary : c.divider,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
