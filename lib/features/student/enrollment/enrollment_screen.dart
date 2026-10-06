/// enrollment_screen.dart — single-course enrollment / payment.
///
/// Works on Flutter Mobile (full screen) and Web (centred, max 560 px).
/// STC Pay and bank transfer are gone; what's left is saved cards (Moyasar),
/// a new card, and free enrollment.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../shared/profile/course_instractor_profile.dart';
import '../../student/models.dart';
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
        ChangeNotifierProvider(create: (_) =>
        EnrollmentProvider(course)
          ..scheduleInitialLoad()),
        ChangeNotifierProvider(create: (_) => SavedMethodsProvider()),
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
      child: switch (enroll.step) {
        EnrollStep.method => const _MethodStep(key: ValueKey('method')),
        EnrollStep.verifying =>
        const PaymentVerifyingView(key: ValueKey('verifying')),
        EnrollStep.pending =>
            PaymentResultView(
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
                onSecondary: () async {
                  await enroll.loadGatewayConfig();
                  await enroll.ensureQuote();
                  enroll.setStep(EnrollStep.method);
                }
            ),
        EnrollStep.success =>
            PaymentResultView(
              key: const ValueKey('success'),
              kind: ResultKind.success,
              title: 'enroll_success_title'.tr,
              message: 'enroll_success_message'.tr,
              primaryLabel: 'start_learning_now'.tr,
              onPrimary: () => popToHome(context),
            ),
        EnrollStep.failed =>
            PaymentResultView(
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
    final wide = isWideLayout(context);
    final quote = enroll.quote;

    final label = enroll.isFree
        ? 'enroll_free_now'.tr
        : quote == null
        ? 'continue'.tr
        : '${'pay_action'.tr} ${quote.fmt(quote.total)} ${enroll
        .currencySymbol}';

    return CenteredBody(
      child: Column(children: [
        enrollAppBar(
            enroll.isFree ? 'enroll_course_title'.tr : 'complete_payment_title'
                .tr),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                wide ? 32 : 20, 12, wide ? 32 : 20, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _CourseSummaryCard(
                  course: enroll.course, currencySymbol: enroll.currencySymbol),
              const SizedBox(height: 24),
              if (enroll.isFree)
                const _FreeCourseBanner()
              else
                ...[
                  const _PaymentMethodPicker(),
                  const SizedBox(height: 20),
                  FeeBreakdownCard(
                      quote: quote, currencySymbol: enroll.currencySymbol),
                ],
            ]),
          ),
        ),
        EnrollConfirmBar(
          label: label,
          loading: enroll.isLoading,
          onTap: () => enroll.confirm(context),
        ),
      ]),
    );
  }
}

// ── Course summary ────────────────────────────────────────────────────────────

class _CourseSummaryCard extends StatelessWidget {
  final CourseModel course;
  final String currencySymbol;

  const _CourseSummaryCard(
      {required this.course, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary.withValues(alpha: .04), c.cardBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: .12)),
        boxShadow: c.cardShadow,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AppNetworkImage(
            url: course.imageUrl,
            width: 76,
            height: 76,
            heroTag: 'course-enrollment-${course.id}',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((AppConfig.lang == 'ar' ? course.titleAr : course.titleEn)??'',
                style: c.h3.copyWith(fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (course.teacher != null) InstructorAvatar(
                teacher: course.teacher!, size: 50, canOpen: true),
            const SizedBox(height: 10),
            Row(children: [
              _PriceBadge(price: course.finalPrice ?? 0,
                  currencySymbol: currencySymbol),
              const SizedBox(width: 8),
              _TypeTag(type: course.type),
            ]),
          ]),
        ),
      ]),
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
            colors: [tone.withValues(alpha: .15), tone.withValues(alpha: .06)]),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: .3)),
      ),
      child: Text(
        isFree ? 'free'.tr : '${price.toStringAsFixed(2)} $currencySymbol',
        style: c.label.copyWith(
            color: tone, fontWeight: FontWeight.w800, fontSize: 12),
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
      decoration: BoxDecoration(color: tone.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6)),
      child: Text(isLive ? 'type_tag_live'.tr : 'type_tag_recorded'.tr,
          style: c.caption.copyWith(
              color: tone, fontWeight: FontWeight.w700, fontSize: 11)),
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
            c.success.withValues(alpha: .04)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.success.withValues(alpha: .3)),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: c.success.withValues(alpha: .12), shape: BoxShape.circle),
          child: Icon(Icons.card_giftcard_rounded, color: c.success, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('free_course_banner_title'.tr,
                style: c.h3.copyWith(color: c.success)),
            const SizedBox(height: 4),
            Text('free_banner_subtitle'.tr, style: c.caption),
          ]),
        ),
      ]),
    );
  }
}

// ── Payment method picker ─────────────────────────────────────────────────────

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker();

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final c = context.colors;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [c.primary, c.primary.withValues(alpha: .7)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
              Icons.payment_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text('payment_method'.tr, style: c.h3.copyWith(fontSize: 15)),
      ]),
      const SizedBox(height: 14),
      // if (enroll.supportsSavedCards)
      //   for (final card in cards)
      //     _MethodTile(
      //       selected: enroll.selectedCard?.id == card.id,
      //       icon: Icons.credit_card_rounded,
      //       iconColor: _brandColor(card.cardBrand),
      //       title: card.displayTitle,
      //       subtitle: '${card.cardBrand?.feeLabel ?? ''} رسوم المعالجة',
      //       badge: card.isDefault ? 'افتراضية' : null,
      //       onTap: () => enroll.selectSavedCard(card),
      //     ),
      if (!(enroll.gateway?.instapayEnabled ?? false))
        _MethodTile(
          selected: enroll.selectedCard == null,
          icon: Icons.add_card_rounded,
          iconColor: _kNewCardColor,
          title: 'new_card_title'.tr,
          subtitle: 'new_card_subtitle'.tr,
          customBadge: const _SecureBadge(),
          onTap: enroll.selectNewCard,
        ),
      if (enroll.gateway?.bankTransferEnabled ?? false)
        _MethodTile(
          selected: enroll.selectedManualMethod == 'bank_transfer',
          icon: Icons.account_balance_rounded,
          iconColor: const Color(0xFF2E7D32),
          title: 'transfer_bank_title'.tr,
          subtitle: 'bank_transfer_subtitle'.tr,
          onTap: () => enroll.selectManualMethod('bank_transfer'),
        ),
      if (enroll.gateway?.instapayEnabled ?? false)
        _MethodTile(
          selected: enroll.selectedManualMethod == 'instapay',
          icon: Icons.qr_code_2_rounded,
          iconColor: const Color(0xFF6A1B9A),
          title: 'transfer_instapay_title'.tr,
          subtitle: 'instapay_subtitle'.tr,
          onTap: () => enroll.selectManualMethod('instapay'),
        ),
    ]);
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_rounded, size: 9, color: Colors.green),
          const SizedBox(width: 3),
          Text('secure_badge'.tr,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                  fontFamily: 'bahji')),
        ]),
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
              color: selected ? c.primary : c.divider, width: selected ? 2 : 1),
          boxShadow: selected
              ? [
            BoxShadow(color: c.primary.withValues(alpha: .14),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]
              : c.cardShadow,
        ),
        child: Row(children: [
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
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(title,
                      style: c.label.copyWith(
                          color: selected ? c.primary : c.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(badge!,
                        style: c.caption.copyWith(
                            color: Colors.amber.shade800, fontSize: 10)),
                  ),
                ],
                if (customBadge != null) ...[
                  const SizedBox(width: 6),
                  customBadge!
                ],
              ]),
              const SizedBox(height: 3),
              Text(subtitle, style: c.caption.copyWith(fontSize: 11)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.primary : Colors.transparent,
              border: Border.all(
                  color: selected ? c.primary : c.divider, width: 2),
            ),
            child: selected ? const Icon(
                Icons.check_rounded, size: 13, color: Colors.white) : null,
          ),
        ]),
      ),
    );
  }
}