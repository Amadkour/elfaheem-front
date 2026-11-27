/// enrollment_screen.dart — single-course enrollment / payment.
///
/// Works on Flutter Mobile (full screen) and Web (centred, max 560 px).
/// STC Pay and bank transfer are gone; what's left is saved cards (Moyasar),
/// a new card, and free enrollment.
library;

import 'package:flutter_education_app/design/app_badges.dart' show AppStatusBadge, AppTone, appInkOn, appTintOn;
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppNeedsConnection;
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart' show offlineReadsOnline;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart' show CourseCoverArt, coursePrimaryInk;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/design/app_hero.dart' show AppHero;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/payments/enrollment/saved_cards/saved_payment_models.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/features/profile/course_instractor_profile.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_models.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart';
import 'package:flutter_education_app/features/rewards/coupon_field.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart' show CouponTarget;
import 'package:flutter_education_app/core/app_digits.dart';


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

    return ValueListenableBuilder<bool>(
      valueListenable: offlineReadsOnline(),
      builder: (context, online, _) => EnrollScaffold(
      child: enroll.isLoading
          ? const AppListSkeleton(items: 4)
          // the checkout could not load its methods and the app is offline (QA_PHASE7 W-4): say so, never skeletons
          : !online && enroll.gateway == null && enroll.step == EnrollStep.method
          ? Column(children: [
              enrollAppBar('complete_payment_title'.tr),
              Expanded(child: AppNeedsConnection(onRetry: enroll.prepareMethodStep)),
            ])
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
                title: enroll.refused
                    ? 'enroll_refused_title'.tr
                    : enroll.manualTransferRejected
                        ? ResultCopy.rejectedTitle
                        : ResultCopy.failedTitle,
                message: enroll.failureReason ?? ResultCopy.failedFallback,
                // a refusal (403) can never succeed on retry: back to the course instead
                primaryLabel: enroll.refused
                    ? 'enroll_refused_back'.tr
                    : enroll.manualTransferRejected
                        ? 'resend_transfer_request'.tr
                        : 'try_again_payment'.tr,
                onPrimary: enroll.refused ? () => Navigator.of(context).maybePop() : enroll.backToMethod,
                secondaryLabel: 'back_to_home'.tr,
                onSecondary: () => popToHome(context),
              ),
            },
      ),
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
            // redesign S-D (Stu2Money `screen=enroll`): "تشترك الحين في" + the course on the money hero, the review
            // card riding up over it
            child: SdHeroList(
              hero: AppHero(
                kicker: 'sd_enroll_kicker'.tr,
                title: (AppConfig.lang == 'ar' ? enroll.course.titleAr : enroll.course.titleEn) ?? '',
                icon: Icons.menu_book_outlined,
              ),
                children: [
                  _CourseSummaryCard(
                    course: enroll.course,
                    currencySymbol: enroll.currencySymbol,
                    price: enroll.selectedOption?.finalPrice,
                  ),
                  if (!enroll.optionsLoaded)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpace.lg),
                      child: AppListSkeleton(items: 3, padding: EdgeInsets.zero),
                    )
                  else if (enroll.isFree)
                    const _FreeCourseBanner()
                  else ...[
                    const _PricePlanPicker(),
                    const _PaymentMethodPicker(),
                    // Games v3: one coupon off the plan price (card / wallet; a transfer goes without one)
                    if (enroll.selectedManualMethod == null) ...[
                      const SizedBox(height: AppSpace.md),
                      CouponField(
                        key: const ValueKey('enroll.coupon'),
                        target: CouponTarget.course,
                        targetId: int.tryParse(enroll.course.id),
                        plan: enroll.selectedPlan,
                        enabled: !enroll.isLoading,
                        onChanged: enroll.setCoupon,
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    FeeBreakdownCard(
                      quote: quote,
                      currencySymbol: enroll.currencySymbol,
                    ),
                  ],
                ],
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
    appDigits('${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)} $symbol'); // platform_settings.digits

/// A section of the checkout: an editorial heading beside a quiet glyph, with the editorial rhythm (32 above it,
/// 12 under it — the space above comes from [AppSpace.sectionHead]).
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: AppSpace.sectionHead,
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(title, style: AppType.section(context))),
        ],
      ),
    );
  }
}

// ── Course summary ────────────────────────────────────────────────────────────

/// The checkout's one block: the course in its own tone (the tone its card wears in every list), its cover, the
/// title in the editorial headline, the teacher, the price and the kind of course.
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

  /// The cover's side.
  static const double _cover = 92;

  @override
  Widget build(BuildContext context) {
    final title = (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? '';
    return AppBlock(
      tone: AppBlockTone.forKey(title),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              // concentric with the block: its radius less the inset
              borderRadius: BorderRadius.circular(AppRadius.block - AppSpace.xs),
              child: course.imageUrl.trim().isEmpty
                  ? CourseCoverArt(
                      seed: title.hashCode,
                      width: _cover,
                      height: _cover,
                      label: title,
                      toneKey: 'cover:$title',
                    )
                  : AppNetworkImage(
                      url: course.imageUrl,
                      width: _cover,
                      height: _cover,
                      heroTag: 'course-enrollment-${course.id}',
                    ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.headline(context).copyWith(color: b.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (course.teacher != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    InstructorAvatar(
                      teacher: course.teacher!,
                      size: AppTouch.min,
                      canOpen: true,
                      showTitle: true,
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
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
        );
      }),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final double price;
  final String currencySymbol;

  const _PriceBadge({required this.price, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final isFree = price == 0;
    return AppStatusBadge(
      label: isFree ? 'free'.tr : '${price.toStringAsFixed(2)} $currencySymbol',
      tone: isFree ? AppTone.success : AppTone.brand,
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String type;

  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    // the strings carry a "🔴" / "▶" mark: the badge draws its own dot / icon instead (no emoji as icons)
    final label = (isLive ? 'type_tag_live'.tr : 'type_tag_recorded'.tr)
        .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
    return AppStatusBadge(
      label: label,
      tone: isLive ? AppTone.danger : AppTone.neutral,
      dot: isLive,
      icon: isLive ? null : Icons.play_arrow_rounded,
    );
  }
}

/// A free course: an emerald block (nothing to pay — it is already "yours"), the gift on a paper plate.
class _FreeCourseBanner extends StatelessWidget {
  const _FreeCourseBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: AppBlock(
        tone: AppBlockTone.emerald,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(
            children: [
              Container(
                width: AppTouch.primary,
                height: AppTouch.primary,
                decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll),
                child: Icon(Icons.card_giftcard_rounded, color: b.accentInk(c.success), size: AppIconSize.lg),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('free_course_banner_title'.tr, style: AppType.section(context).copyWith(color: b.ink)),
                    const SizedBox(height: AppSpace.xxs),
                    Text('free_banner_subtitle'.tr, style: AppType.body(context).copyWith(color: b.muted)),
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
        if (options.length == 1)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IntrinsicHeight(
              child: _PlanTile(
                option: options[0],
                selected: enroll.selectedPlan == options[0].plan,
                currencySymbol: enroll.currencySymbol,
                savePercent: _savePercent(options, options[0]),
                isBestValue: options[0].plan == bestPlan,
                onTap: () => enroll.selectPlan(options[0].plan),
              ),
            ),
          )
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: _PlanTile(
                      option: options[i],
                      selected: enroll.selectedPlan == options[i].plan,
                      currencySymbol: enroll.currencySymbol,
                      savePercent: _savePercent(options, options[i]),
                      isBestValue: options[i].plan == bestPlan,
                      onTap: () => enroll.selectPlan(options[i].plan),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One plan: paper on a warm hairline; the chosen one carries the primary ring and tint (system.md: emerald for
/// selection). The monthly cost is the plan's figure, the whole plan's total sits in an inset well under it.
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

  /// A lone plan stays a card, not a full-width band.
  static const double _maxWidth = 240;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);

    final m = PlanKeys.months(option.plan);
    final months = m <= 0 ? 1 : m;
    final perMonth = option.finalPrice / months;
    final ink = selected ? coursePrimaryInk(context) : c.textDark;
    const tabular = [FontFeature.tabularFigures()];

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AppPressScale(
          child: AnimatedContainer(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            duration: motion.base,
            curve: AppEase.out,
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: selected ? c.primaryTint : c.cardBg,
              borderRadius: AppRadius.cardAll,
              border: Border.all(
                color: selected ? c.primary : c.divider,
                width: selected ? AppBorder.focus : AppBorder.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RadioDot(selected: selected),
                const SizedBox(height: AppSpace.sm),
                // ── Title ────────────────────────────────────────────────────
                Text(
                  PlanKeys.titleKey(option.plan).tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.section(context).copyWith(color: ink),
                ),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(PlanKeys.accessKey(option.plan).tr, style: AppType.meta(context)),
                // the saving, or "Best value" on the biggest one (gold: a top mark), on its own line so it never
                // has to share the tile's width with the radio
                if (isBestValue || savePercent != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  isBestValue
                      ? AppStatusBadge(label: 'plan_best_value'.tr, tone: AppTone.gold, dense: true)
                      : AppStatusBadge(label: '${'plan_save'.tr} $savePercent%', tone: AppTone.success, dense: true),
                ],
                const SizedBox(height: AppSpace.sm),
                // ── Monthly cost (the plan's figure), "/ month" under it ─────
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _fmtMoney(perMonth, currencySymbol),
                    style: AppType.figure(context).copyWith(color: ink, fontFeatures: tabular),
                  ),
                ),
                Text('plan_per_month'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                const Spacer(),
                const SizedBox(height: AppSpace.sm),
                // ── Total for the whole plan ─────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
                  decoration: BoxDecoration(
                    color: selected ? c.cardBg : c.inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.control - AppSpace.xxs),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long_rounded, size: AppIconSize.xs, color: c.textMedium),
                          const SizedBox(width: AppSpace.xxs),
                          Flexible(
                            child: Text(
                              'plan_total'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.meta(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xxs / 2),
                      Wrap(
                        spacing: AppSpace.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (option.hasDiscount)
                            Text(
                              _fmtMoney(option.price, currencySymbol),
                              style: AppType.meta(context).copyWith(
                                color: c.textLight,
                                fontFeatures: tabular,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: c.textLight,
                              ),
                            ),
                          Text(
                            _fmtMoney(option.finalPrice, currencySymbol),
                            style: AppType.bodyStrong(context).copyWith(color: ink, fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
      duration: AppMotion.of(context).fast,
      curve: AppEase.out,
      width: AppIconSize.lg,
      height: AppIconSize.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.primary : Colors.transparent,
        border: Border.all(color: selected ? c.primary : c.divider, width: AppBorder.focus),
      ),
      child: selected ? Icon(Icons.check_rounded, size: AppIconSize.xs, color: c.onHero) : null,
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
        enroll.selectedCard == null &&
        enroll.selectedManualMethod == null &&
        enroll.selectedWallet == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: Icons.payment_rounded, title: 'payment_method'.tr),
        if (g == null || !g.anyMethodEnabled)
          _NoMethodsNotice(onRetry: enroll.prepareMethodStep)
        else ...[
          // Saved cards exactly as the backend returned them (only while card payments are open).
          for (final card in enroll.availableSavedCards)
            _MethodTile(
              selected: enroll.selectedCard?.id == card.id,
              icon: Icons.credit_card_rounded,
              iconColor: _brandColor(context, card.cardBrand?.apiKey),
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
              iconColor: context.colors.primary,
              // "مدى" only where the payer's country has it (RULES §3)
              title: (g.madaOffered ? 'new_card_title' : 'intl_new_card_title').tr,
              subtitle: (g.madaOffered ? 'new_card_subtitle' : 'intl_new_card_subtitle').tr,
              customBadge: const _SecureBadge(),
              onTap: enroll.selectNewCard,
            ),
          // Apple Pay / Google Pay — only the ones the admin opened AND this device/gateway can use.
          for (final w in enroll.availableWallets)
            _MethodTile(
              selected: enroll.selectedWallet == w.type,
              icon: w.type == 'apple_pay'
                  ? Icons.apple
                  : Icons.account_balance_wallet_rounded,
              iconColor: w.type == 'apple_pay'
                  ? context.colors.textDark
                  : context.colors.primary,
              title:
                  g.labelFor(w.type) ??
                  (w.type == 'apple_pay' ? 'Apple Pay' : 'Google Pay'),
              subtitle: AppConfig.lang == 'ar'
                  ? 'ادفع بسرعة وأمان'
                  : 'Pay fast and securely',
              customBadge: const _SecureBadge(),
              onTap: () => enroll.selectWallet(w.type),
            ),
          if (g.bankTransferEnabled)
            _MethodTile(
              selected: enroll.selectedManualMethod == 'bank_transfer',
              icon: Icons.account_balance_rounded,
              iconColor: context.colors.success,
              title: g.labelFor('bank_transfer') ?? 'transfer_bank_title'.tr,
              subtitle: 'bank_transfer_subtitle'.tr,
              onTap: () => enroll.selectManualMethod('bank_transfer'),
            ),
          if (g.instapayEnabled)
            _MethodTile(
              selected: enroll.selectedManualMethod == 'instapay',
              icon: Icons.qr_code_2_rounded,
              iconColor: context.colors.purple,
              title: g.labelFor('instapay') ?? 'transfer_instapay_title'.tr,
              subtitle: 'instapay_subtitle'.tr,
              onTap: () => enroll.selectManualMethod('instapay'),
            ),
        ],
      ],
    );
  }
}

/// Tile colour per card network: the networks' own brand colours (falls back to the theme's primary). These are
/// the networks' identities, not the app's palette, so they stay fixed in every theme.
Color _brandColor(BuildContext context, String? apiKey) => switch (apiKey?.toLowerCase()) {
  'mada' => const Color(0xFF0B8A4F),
  'visa' => const Color(0xFF1A1F71),
  'mastercard' || 'master' => const Color(0xFFEB001B),
  'amex' || 'american_express' => const Color(0xFF2E77BB),
  _ => context.colors.primary,
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
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(
        children: [
          Icon(Icons.payments_outlined, size: AppIconSize.xl, color: c.textLight),
          const SizedBox(height: AppSpace.sm),
          Text(
            'payment_no_methods_available'.tr,
            style: AppType.body(context).copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.xs),
          AppButton.ghost(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) =>
      AppStatusBadge(label: 'secure_badge'.tr, tone: AppTone.success, icon: Icons.lock_rounded, dense: true);
}

/// One way to pay: paper on a warm hairline, its mark in a tinted well; the chosen one carries the primary ring
/// and tint and a filled check at the end.
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
    final motion = AppMotion.of(context);
    final well = appTintOn(context, iconColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AppPressScale(
            child: AnimatedContainer(
              duration: motion.base,
              curve: AppEase.out,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: selected ? c.primaryTint : c.cardBg,
                borderRadius: AppRadius.cardAll,
                border: Border.all(
                  color: selected ? c.primary : c.divider,
                  width: selected ? AppBorder.focus : AppBorder.hairline,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: AppTouch.min,
                    height: AppTouch.min,
                    decoration: BoxDecoration(color: well, borderRadius: AppRadius.controlAll),
                    child: Icon(icon, color: appInkOn(context, iconColor, well), size: AppIconSize.lg),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: AppSpace.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: AppType.row(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: selected ? coursePrimaryInk(context) : c.textDark,
                              ),
                            ),
                            if (badge != null) AppStatusBadge(label: badge!, tone: AppTone.brand, dense: true),
                            ?customBadge,
                          ],
                        ),
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text(subtitle, style: AppType.meta(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  _RadioDot(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
