/// enrollment_screen.dart — FINAL
///
/// FIXES APPLIED:
///  1. _StcOtpStep replaced by the premium StcOtpStep from stc_otp_step.dart
///     (shake animation, 6-box input, auto-focus, paste, resend timer)
///  2. Removed the old dead _StcOtpStep class
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'enrollment_provider.dart';
import 'stc_otp_step.dart'; // premium OTP widget

// ── Entry ─────────────────────────────────────────────────────────────────────

class EnrollmentScreen extends StatelessWidget {
  final CourseModel course;
  const EnrollmentScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EnrollmentProvider(course)),
        ChangeNotifierProvider(create: (_) => SavedMethodsProvider()..fetch()),
      ],
      child: const _EnrollView(),
    );
  }
}

// ── Root switcher ─────────────────────────────────────────────────────────────

class _EnrollView extends StatelessWidget {
  const _EnrollView();
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Consumer<EnrollmentProvider>(
            builder: (_, enroll, __) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.04, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: c,
                ),
              ),
              child: switch (enroll.step) {
                EnrollStep.method    => const _MethodStep(key:    ValueKey('m')),
                EnrollStep.stcMobile => const _StcMobileStep(key: ValueKey('sm')),
                EnrollStep.stcOtp    => const StcOtpStep(key:     ValueKey('so')), // ← premium widget
                EnrollStep.bankDetails => const _BankStep(key:    ValueKey('b')),
                EnrollStep.verifying => const _VerifyingStep(key: ValueKey('v')),
                EnrollStep.success   => const _SuccessStep(key:   ValueKey('ok')),
                EnrollStep.failed    => const _FailedStep(key:    ValueKey('f')),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Moyasar card payment screen ───────────────────────────────────────────────
// Pushed by enrollment_provider for the mobile new-card flow

class MoyasarCardPaymentScreen extends StatelessWidget {
  final PaymentConfig config;
  final void Function(dynamic) onPaymentResult;
  const MoyasarCardPaymentScreen(
      {super.key, required this.config, required this.onPaymentResult});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات البطاقة',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: CreditCard(config: config, onPaymentResult: onPaymentResult),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — Method picker
// ─────────────────────────────────────────────────────────────────────────────

class _MethodStep extends StatelessWidget {
  const _MethodStep({super.key});
  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    return Column(
      children: [
        ScreenAppBar(title: enroll.isFree ? 'تسجيل في الكورس' : 'إتمام الدفع'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CourseSummaryCard(course: enroll.course),
                const SizedBox(height: 22),
                if (enroll.isFree)
                  _FreeCourseBanner()
                else ...[
                  const _SavedMethodPicker(),
                  const SizedBox(height: 20),
                  const _FeeBreakdownCard(),
                ],
              ],
            ),
          ),
        ),
        const _ConfirmBar(),
      ],
    );
  }
}

class _CourseSummaryCard extends StatelessWidget {
  final CourseModel course;
  const _CourseSummaryCard({required this.course});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: c.cardShadow),
      child: Row(children: [
        AppNetworkImage(
            url: course.imageUrl,
            width: 80,
            height: 80,
            borderRadius: BorderRadius.circular(12)),
        const SizedBox(width: 14),
        Expanded(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(course.name,
                style: c.h3, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            if ((course.teacherName ?? '').isNotEmpty)
              Text(course.teacherName!, style: c.caption),
            const SizedBox(height: 8),
            Row(children: [
              _PriceBadge(price: course.price),
              const SizedBox(width: 8),
              _TypeTag(type: course.type ?? ''),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final double price;
  const _PriceBadge({required this.price});
  @override
  Widget build(BuildContext context) {
    final isFree = price == 0;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: (isFree ? c.success : c.accent).withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(isFree ? 'مجاني' : '${price.toStringAsFixed(2)} ر.س',
          style: c.label.copyWith(
              color: isFree ? c.success : c.accent,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String type;
  const _TypeTag({required this.type});
  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: (isLive ? c.danger : c.primary).withValues(alpha: .1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(isLive ? '🔴 مباشر' : '▶ مسجّل',
          style: c.caption.copyWith(
              color: isLive ? c.danger : c.primary,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _FreeCourseBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: c.success.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.success.withValues(alpha: .3))),
      child: Row(children: [
        Icon(Icons.card_giftcard_rounded, color: c.success, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('هذا الكورس مجاني! 🎉',
                style: c.h3.copyWith(color: c.success)),
            const SizedBox(height: 4),
            Text('اضغط "سجّل الآن" للحصول على وصول فوري.', style: c.caption),
          ]),
        ),
      ]),
    );
  }
}

// ── Method picker tiles ───────────────────────────────────────────────────────

class _SavedMethodPicker extends StatefulWidget {
  const _SavedMethodPicker();
  @override
  State<_SavedMethodPicker> createState() => _SavedMethodPickerState();
}

class _SavedMethodPickerState extends State<_SavedMethodPicker> {
  int _sel = -2; // -2=newCard  -1=bank  -3=stc  0..n=saved card index

  @override
  Widget build(BuildContext context) {
    final savedP = context.watch<SavedMethodsProvider>();
    final enrollP = context.read<EnrollmentProvider>();
    final c = context.colors;
    final cards = savedP.cards;

    Color brandColor(CardBrand? b) => switch (b) {
      CardBrand.mada => const Color(0xFF1B4332),
      CardBrand.visa => const Color(0xFF1A237E),
      CardBrand.mastercard => const Color(0xFFB71C1C),
      _ => const Color(0xFF263238),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.payment_rounded, size: 18, color: c.primary),
          ),
          const SizedBox(width: 10),
          Text('طريقة الدفع', style: c.h3.copyWith(fontSize: 15)),
        ]),
        const SizedBox(height: 14),

        // Saved cards
        ...cards.asMap().entries.map((e) => _MethodTile(
          selected: _sel == e.key,
          icon: Icons.credit_card_rounded,
          iconColor: brandColor(e.value.cardBrand),
          title: e.value.displayTitle,
          subtitle: '${e.value.cardBrand?.feeLabel ?? ''} رسوم المعالجة',
          badge: e.value.isDefault ? 'افتراضية' : null,
          onTap: () {
            setState(() => _sel = e.key);
            enrollP.selectSavedCard(e.value);
          },
        )),

        // STC Pay
        _MethodTile(
          selected: _sel == -3,
          icon: Icons.sim_card_rounded,
          iconColor: const Color(0xFF4A148C),
          title: 'STC Pay',
          subtitle: '2.5% + 1 ر.س رسوم المعالجة',
          onTap: () {
            setState(() => _sel = -3);
            enrollP.selectStcPay();
          },
        ),

        // Bank transfer
        _MethodTile(
          selected: _sel == -1,
          icon: Icons.account_balance_rounded,
          iconColor: const Color(0xFF2D6A4F),
          title: 'تحويل بنكي',
          subtitle: 'بدون رسوم — مراجعة يدوية (24 ساعة)',
          onTap: () {
            setState(() => _sel = -1);
            enrollP.selectBankTransfer();
          },
        ),

        // New card via Moyasar SDK
        _MethodTile(
          selected: _sel == -2,
          icon: Icons.add_card_rounded,
          iconColor: c.accent,
          title: 'بطاقة ائتمانية / مدى جديدة',
          subtitle: 'مدى · فيزا · ماستركارد — آمن PCI-DSS عبر Moyasar SDK',
          onTap: () {
            setState(() => _sel = -2);
            enrollP.selectNewCard();
          },
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final String? badge;
  final VoidCallback onTap;
  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: .05) : c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? c.primary : c.divider,
              width: selected ? 2 : 1),
          boxShadow: selected ? c.primaryShadow : c.cardShadow,
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title,
                    style: c.label.copyWith(
                        color: selected ? c.primary : c.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(badge!,
                        style: c.caption
                            .copyWith(color: Colors.amber[800], fontSize: 10)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(subtitle, style: c.caption.copyWith(fontSize: 11)),
            ]),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.primary : Colors.transparent,
              border: Border.all(
                  color: selected ? c.primary : c.divider, width: 2),
            ),
            child: selected
                ? const Icon(Icons.check_rounded,
                size: 12, color: Colors.white)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ── Fee breakdown ─────────────────────────────────────────────────────────────

class _FeeBreakdownCard extends StatelessWidget {
  const _FeeBreakdownCard();
  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final savedP = context.watch<SavedMethodsProvider>();
    final fees = enroll.computedFees(savedP);
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: c.cardShadow,
          border: Border.all(color: c.divider)),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.receipt_long_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Text('تفاصيل الفاتورة', style: c.h3.copyWith(fontSize: 14)),
        ]),
        const SizedBox(height: 14),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: 12),
        _FeeRow(label: 'سعر الكورس', value: fees.fmt(fees.coursePrice)),
        _FeeRow(
            label: 'رسوم المنصة (10%)', value: fees.fmt(fees.platformFee)),
        _FeeRow(
            label: 'ضريبة القيمة المضافة (15%)',
            value: fees.fmt(fees.vatOnPlatform)),
        _FeeRow(
            label: 'رسوم بوابة الدفع',
            value: fees.fmt(fees.gatewayFee),
            sub: fees.gatewayLabel),
        const SizedBox(height: 10),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('الإجمالي', style: c.h2.copyWith(fontSize: 17)),
          Text(fees.fmt(fees.total),
              style: c.h2.copyWith(color: c.primary, fontSize: 19)),
        ]),
      ]),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label, value;
  final String? sub;
  const _FeeRow({required this.label, required this.value, this.sub});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: c.body.copyWith(fontSize: 13)),
              if (sub != null) Text(sub!, style: c.caption.copyWith(fontSize: 10)),
            ])),
        Text(value, style: c.label.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Confirm bar ───────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar();
  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final savedP = context.watch<SavedMethodsProvider>();
    final fees = enroll.isFree ? null : enroll.computedFees(savedP);
    final label = enroll.isFree
        ? 'سجّل مجاناً الآن'
        : fees == null
        ? 'متابعة'
        : 'ادفع ${fees.fmt(fees.total)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
          color: context.colors.cardBg,
          boxShadow: context.colors.bottomNavShadow),
      child: GestureDetector(
        onTap:
        enroll.isLoading ? null : () => enroll.confirm(savedP, context),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
              gradient: context.colors.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: context.colors.primaryShadow),
          child: Center(
            child: enroll.isLoading
                ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
                : Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    fontFamily: 'Cairo')),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP — STC Mobile number entry
// ─────────────────────────────────────────────────────────────────────────────

class _StcMobileStep extends StatefulWidget {
  const _StcMobileStep({super.key});
  @override
  State<_StcMobileStep> createState() => _StcMobileStepState();
}

class _StcMobileStepState extends State<_StcMobileStep> {
  final _ctrl = TextEditingController();
  String? _err;
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final m = _ctrl.text.trim();
    if (m.length < 9) {
      setState(() => _err = 'أدخل رقم جوال صحيح');
      return;
    }
    setState(() => _err = null);
    await context.read<EnrollmentProvider>().initStcPay(m, context);
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final c = context.colors;
    return Column(children: [
      _BackBar(title: 'STC Pay', onBack: enroll.retryFromStart),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        boxShadow: [
                          BoxShadow(
                              color:
                              const Color(0xFF4A148C).withValues(alpha: .35),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      child: const Icon(Icons.sim_card_rounded,
                          color: Colors.white, size: 44),
                    )),
                const SizedBox(height: 20),
                Text('أدخل رقم جوالك المسجّل في STC Pay',
                    style: c.h2.copyWith(fontSize: 18),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('سيصلك رمز تحقق SMS لإتمام الدفع.',
                    style: c.body.copyWith(height: 1.7),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                      color: c.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _err != null ? c.danger : c.divider),
                      boxShadow: c.cardShadow),
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    style: c.label.copyWith(fontSize: 18, letterSpacing: 2),
                    decoration: InputDecoration(
                      hintText: '05XXXXXXXX',
                      hintStyle: c.caption,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.phone_android_rounded,
                          color: c.primary),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 8),
                  Text(_err!,
                      style: c.caption.copyWith(color: c.danger),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 28),
                _PrimaryBtn(
                  label: 'إرسال رمز التحقق',
                  color1: const Color(0xFF4A148C),
                  color2: const Color(0xFF7B1FA2),
                  loading: enroll.isLoading,
                  onTap: _submit,
                ),
              ]),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP — Bank transfer
// ─────────────────────────────────────────────────────────────────────────────

class _BankStep extends StatelessWidget {
  const _BankStep({super.key});
  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final info = enroll.bankInfo;
    final c = context.colors;
    return Column(children: [
      ScreenAppBar(title: 'بيانات التحويل'),
      Expanded(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(16),
                  border:
                  Border.all(color: c.primary.withValues(alpha: .2))),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: c.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                          'حوّل المبلغ مع ذكر رقم المرجع. سيتم تفعيل كورسك خلال 24 ساعة.',
                          style: c.body.copyWith(color: c.primary, height: 1.6),
                        )),
                  ]),
            ),
            const SizedBox(height: 20),
            if (info != null) ...[
              _BankTile(
                  label: 'المبلغ',
                  value:
                  '${(info['fees']?['total'] as num?)?.toStringAsFixed(2) ?? '—'} ر.س',
                  highlight: true),
              const SizedBox(height: 10),
              _BankTile(
                  label: 'رقم المرجع',
                  copyable: true,
                  golden: true,
                  value:
                  info['instructions']?['reference'] as String? ?? '—'),
              const SizedBox(height: 10),
              _BankTile(
                  label: 'اسم البنك',
                  value:
                  info['instructions']?['bank_name'] as String? ?? '—'),
              const SizedBox(height: 10),
              _BankTile(
                  label: 'صاحب الحساب',
                  copyable: true,
                  value: info['instructions']?['account_name'] as String? ??
                      '—'),
              const SizedBox(height: 10),
              _BankTile(
                  label: 'الآيبان IBAN',
                  copyable: true,
                  mono: true,
                  value: info['instructions']?['iban'] as String? ?? '—'),
            ],
            const SizedBox(height: 28),
            _PrimaryBtn(
                label: 'تم التحويل ✓',
                onTap: enroll.confirmBankTransfer),
            const SizedBox(height: 12),
            _SecondaryBtn(label: 'العودة', onTap: enroll.backToMethod),
          ]),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP — Verifying
// ─────────────────────────────────────────────────────────────────────────────

class _VerifyingStep extends StatelessWidget {
  const _VerifyingStep({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(
          width: 72,
          height: 72,
          child:
          CircularProgressIndicator(color: c.primary, strokeWidth: 3)),
      const SizedBox(height: 28),
      Text('جارٍ تأكيد الدفع...',
          style: c.h2.copyWith(fontSize: 18), textAlign: TextAlign.center),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP — Success
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessStep extends StatefulWidget {
  const _SuccessStep({super.key});
  @override
  State<_SuccessStep> createState() => _SuccessStepState();
}

class _SuccessStepState extends State<_SuccessStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale, _fade;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.read<EnrollmentProvider>();
    final pending = enroll.paidViaBankTransfer;
    final c = context.colors;
    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScaleTransition(
                scale: _scale,
                child: Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 32),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: pending
                              ? [c.accent, const Color(0xFFF39C12)]
                              : [c.success, const Color(0xFF2ECC71)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: (pending ? c.accent : c.success)
                                  .withValues(alpha: .4),
                              blurRadius: 28,
                              offset: const Offset(0, 10))
                        ],
                      ),
                      child: Icon(
                        pending
                            ? Icons.hourglass_top_rounded
                            : Icons.check_rounded,
                        color: Colors.white,
                        size: 60,
                      ),
                    ))),
            Text(
                pending ? 'في انتظار التحقق ⏳' : 'تم الدفع بنجاح! 🎉',
                style: c.h1.copyWith(fontSize: 24),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              pending
                  ? 'سيتم تفعيل الكورس خلال 24 ساعة بعد التحقق من التحويل.'
                  : 'تم تأكيد دفعتك وتفعيل الكورس. يمكنك البدء الآن!',
              style: c.body.copyWith(height: 1.7),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _PrimaryBtn(
              label: pending ? 'العودة للرئيسية' : 'ابدأ التعلم الآن',
              onTap: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP — Failed
// ─────────────────────────────────────────────────────────────────────────────

class _FailedStep extends StatelessWidget {
  const _FailedStep({super.key});
  @override
  Widget build(BuildContext context) {
    final enroll = context.read<EnrollmentProvider>();
    final c = context.colors;
    final reason =
        enroll.failureReason ?? 'حدث خطأ. الرجاء المحاولة مرة أخرى.';
    final isSoft = reason.contains('قيد المعالجة') ||
        reason.contains('سيُفعَّل') ||
        reason.contains('تم الدفع');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: Container(
                width: 110,
                height: 110,
                margin: const EdgeInsets.only(bottom: 28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isSoft
                        ? [c.accent, const Color(0xFFF39C12)]
                        : [c.danger, const Color(0xFFE74C3C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  isSoft
                      ? Icons.hourglass_top_rounded
                      : Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              )),
          Text(isSoft ? 'الدفع قيد المعالجة' : 'فشلت عملية الدفع',
              style: c.h1.copyWith(fontSize: 22),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(reason,
              style: c.body.copyWith(height: 1.7),
              textAlign: TextAlign.center),
          const SizedBox(height: 40),
          _PrimaryBtn(
            label: isSoft ? 'العودة للرئيسية' : 'حاول مرة أخرى',
            onTap: isSoft
                ? () =>
                Navigator.of(context).popUntil((r) => r.isFirst)
                : enroll.retryFromStart,
          ),
          const SizedBox(height: 14),
          _SecondaryBtn(
            label: 'العودة للرئيسية',
            onTap: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BackBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _BackBar({required this.title, required this.onBack});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: c.textDark, size: 20),
          onPressed: onBack,
        ),
        Expanded(
            child: Text(title,
                style: c.h2.copyWith(fontSize: 17),
                textAlign: TextAlign.center)),
        const SizedBox(width: 44),
      ]),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final Color? color1, color2;
  const _PrimaryBtn({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.color1,
    this.color2,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = color1 != null
        ? LinearGradient(
        colors: [color1!, color2 ?? color1!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight)
        : c.primaryGradient;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
            gradient: g,
            borderRadius: BorderRadius.circular(30),
            boxShadow: c.primaryShadow),
        child: Center(
          child: loading
              ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
              : Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFamily: 'Cairo')),
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: context.colors.divider)),
      child: Center(
          child: Text(label,
              style: context.colors.label
                  .copyWith(color: context.colors.textMedium))),
    ),
  );
}

class _BankTile extends StatefulWidget {
  final String label, value;
  final bool copyable, highlight, golden, mono;
  const _BankTile(
      {required this.label,
        required this.value,
        this.copyable = false,
        this.highlight = false,
        this.golden = false,
        this.mono = false});
  @override
  State<_BankTile> createState() => _BankTileState();
}

class _BankTileState extends State<_BankTile> {
  bool _copied = false;
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: widget.golden
            ? Colors.amber.withValues(alpha: .07)
            : widget.highlight
            ? c.primary.withValues(alpha: .06)
            : c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: widget.golden
                ? Colors.amber.withValues(alpha: .35)
                : widget.highlight
                ? c.primary.withValues(alpha: .25)
                : c.divider),
      ),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: c.caption.copyWith(fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(
                      widget.value,
                      style: widget.highlight
                          ? c.h2.copyWith(color: c.primary)
                          : widget.golden
                          ? c.h3.copyWith(
                          color: Colors.amber[800], letterSpacing: 1.4)
                          : c.label.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: widget.mono ? 1.5 : 0)),
                ])),
        if (widget.copyable)
          GestureDetector(
            onTap: _copy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _copied
                    ? c.success.withValues(alpha: .12)
                    : c.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                  color: _copied ? c.success : c.primary),
            ),
          ),
      ]),
    );
  }
}