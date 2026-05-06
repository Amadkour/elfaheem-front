/// enrollment_screen.dart  (complete rewrite)
/// Premium Saudi enrollment flow:
///  Free → instant enroll
///  Paid → pick saved card / bank transfer → full fee breakdown → confirm
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../student/models.dart';
import 'enrollment_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

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
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child:   SlideTransition(
                  position: Tween(
                      begin: const Offset(.04, 0), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              child: switch (enroll.step) {
                EnrollStep.method      => const _MethodStep(key: ValueKey('m')),
                EnrollStep.bankDetails => const _BankStep(key: ValueKey('b')),
                EnrollStep.success     => const _SuccessStep(key: ValueKey('s')),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — Method picker + fee breakdown
// ─────────────────────────────────────────────────────────────────────────────

class _MethodStep extends StatelessWidget {
  const _MethodStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final isFree = enroll.isFree;

    return Column(
      children: [
        ScreenAppBar(title: isFree ? 'تسجيل في الكورس' : 'إتمام الدفع'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CourseSummaryCard(course: enroll.course),
                const SizedBox(height: 22),

                if (isFree) ...[
                  _FreeCourseBanner(),
                ] else ...[
                  // ── Saved method picker ──────────────────────────────────
                  _SavedMethodPicker(),
                  const SizedBox(height: 20),
                  // ── Fee breakdown (updates live with selected method) ────
                  _FeeBreakdownCard(),
                ],
              ],
            ),
          ),
        ),
        _ConfirmBar(),
      ],
    );
  }
}

// ── Course Summary ────────────────────────────────────────────────────────────

class _CourseSummaryCard extends StatelessWidget {
  final CourseModel course;
  const _CourseSummaryCard({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        c.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow:    c.cardShadow,
      ),
      child: Row(
        children: [
          AppNetworkImage(
              url:          course.imageUrl,
              width:        80,
              height:       80,
              borderRadius: BorderRadius.circular(12)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name,
                    style:    c.h3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if ((course.teacherName ?? '').isNotEmpty)
                  Text(course.teacherName!, style: c.caption),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _PriceBadge(price: course.price),
                    const SizedBox(width: 8),
                    _TypeTag(type: course.type ?? ''),
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
  const _PriceBadge({required this.price});

  @override
  Widget build(BuildContext context) {
    final isFree = price == 0;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isFree
            ? c.success.withValues(alpha: .1)
            : c.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isFree ? 'مجاني' : '${price.toStringAsFixed(2)} ر.س',
        style: c.label.copyWith(
          color:      isFree ? c.success : c.accent,
          fontWeight: FontWeight.w800,
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
    final isLive = type == 'live';
    final c      = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        (isLive ? c.danger : c.primary).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? '🔴 مباشر' : '▶ مسجّل',
        style: c.caption.copyWith(
          color:      isLive ? c.danger : c.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Free banner ───────────────────────────────────────────────────────────────

class _FreeCourseBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        c.success.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: c.success.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Icon(Icons.card_giftcard_rounded, color: c.success, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('هذا الكورس مجاني! 🎉',
                    style: c.h3.copyWith(color: c.success)),
                const SizedBox(height: 4),
                Text('اضغط "سجّل الآن" للحصول على وصول فوري.',
                    style: c.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Saved Method Picker ───────────────────────────────────────────────────────

class _SavedMethodPicker extends StatefulWidget {
  const _SavedMethodPicker();

  @override
  State<_SavedMethodPicker> createState() => _SavedMethodPickerState();
}

class _SavedMethodPickerState extends State<_SavedMethodPicker> {
  // 0..n-1 = saved card index, -1 = bank transfer, -2 = new card
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final savedP  = context.watch<SavedMethodsProvider>();
    final enrollP = context.read<EnrollmentProvider>();
    final c       = context.colors;
    final cards   = savedP.cards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width:  34, height: 34,
              decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.payment_rounded, size: 18, color: c.primary),
            ),
            const SizedBox(width: 10),
            Text('طريقة الدفع', style: c.h3.copyWith(fontSize: 15)),
          ],
        ),
        const SizedBox(height: 14),

        // ── Saved cards ──────────────────────────────────────────────────
        ...cards.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          return _MethodTile(
            selected:    _selected == i,
            icon:        Icons.credit_card_rounded,
            iconColor:   _brandColor(m.cardBrand),
            title:       m.displayTitle,
            subtitle:    '${m.cardBrand?.feeLabel ?? ''} رسوم المعالجة',
            badge:       m.isDefault ? 'افتراضية' : null,
            onTap: () {
              setState(() => _selected = i);
              enrollP.selectSavedCard(m);
            },
          );
        }),

        // ── Bank transfer ────────────────────────────────────────────────
        _MethodTile(
          selected:  _selected == -1,
          icon:      Icons.account_balance_rounded,
          iconColor: const Color(0xFF2D6A4F),
          title:     'تحويل بنكي',
          subtitle:  'بدون رسوم معالجة — يتطلب تحقق يدوي (24 ساعة)',
          onTap: () {
            setState(() => _selected = -1);
            enrollP.selectBankTransfer();
          },
        ),

        // ── New card (via Moyasar) ────────────────────────────────────────
        _MethodTile(
          selected:  _selected == -2,
          icon:      Icons.add_card_rounded,
          iconColor: c.accent,
          title:     'إضافة بطاقة جديدة',
          subtitle:  'مدى / فيزا / ماستركارد / Apple Pay / STC Pay',
          onTap: () {
            setState(() => _selected = -2);
            enrollP.selectNewCard();
          },
        ),
      ],
    );
  }

  Color _brandColor(CardBrand? b) {
    switch (b) {
      case CardBrand.mada:        return const Color(0xFF1B4332);
      case CardBrand.visa:        return const Color(0xFF1A237E);
      case CardBrand.mastercard:  return const Color(0xFFB71C1C);
      case CardBrand.stcPay:      return const Color(0xFF4A148C);
      default:                    return const Color(0xFF263238);
    }
  }
}

class _MethodTile extends StatelessWidget {
  final bool       selected;
  final IconData   icon;
  final Color      iconColor;
  final String     title, subtitle;
  final String?    badge;
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
          color:        selected
              ? c.primary.withValues(alpha: .05)
              : c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? c.primary : c.divider,
              width: selected ? 2       : 1),
          boxShadow: selected ? c.primaryShadow : c.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width:  42, height: 42,
              decoration: BoxDecoration(
                  color:        iconColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: c.label.copyWith(
                              color:      selected ? c.primary : c.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize:   14)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color:        Colors.amber.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(badge!,
                              style: c.caption.copyWith(
                                  color: Colors.amber[800], fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: c.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            // Radio dot
            Container(
              width:  20, height: 20,
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
          ],
        ),
      ),
    );
  }
}

// ── Fee Breakdown Card ────────────────────────────────────────────────────────

class _FeeBreakdownCard extends StatelessWidget {
  const _FeeBreakdownCard();

  @override
  Widget build(BuildContext context) {
    final enroll  = context.watch<EnrollmentProvider>();
    final savedP  = context.watch<SavedMethodsProvider>();
    final fees    = enroll.computedFees(savedP);
    final c       = context.colors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        c.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow:    c.cardShadow,
        border:       Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text('تفاصيل الفاتورة', style: c.h3.copyWith(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: c.divider, height: 1),
          const SizedBox(height: 12),

          _FeeRow(label: 'سعر الكورس',
              value: fees.fmt(fees.coursePrice)),
          _FeeRow(label: 'رسوم المنصة (10%)',
              value: fees.fmt(fees.platformFee)),
          _FeeRow(label: 'ضريبة القيمة المضافة (15%) على الرسوم',
              value: fees.fmt(fees.vatOnPlatform)),
          _FeeRow(
            label:    'رسوم المعالجة',
            value:    fees.fmt(fees.gatewayFee),
            subLabel: fees.gatewayLabel,
            isGreen:  fees.gatewayFee == 0,
          ),

          const SizedBox(height: 10),
          Divider(color: c.divider, height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: c.h2.copyWith(fontSize: 17)),
              Text(
                fees.fmt(fees.total),
                style: c.h2.copyWith(
                    color: c.primary, fontSize: 19),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String  label, value;
  final String? subLabel;
  final bool    isGreen;

  const _FeeRow({
    required this.label,
    required this.value,
    this.subLabel,
    this.isGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: c.body.copyWith(fontSize: 13)),
                if (subLabel != null)
                  Text(subLabel!, style: c.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Text(
            value,
            style: c.label.copyWith(
              color:      isGreen ? c.success : c.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirm Bar ───────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar();

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final savedP = context.watch<SavedMethodsProvider>();
    final fees   = enroll.isFree ? null : enroll.computedFees(savedP);

    final label = enroll.isFree
        ? 'سجّل مجاناً الآن'
        : fees == null
            ? 'متابعة'
            : 'ادفع ${fees.fmt(fees.total)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color:     context.colors.cardBg,
        boxShadow: context.colors.bottomNavShadow,
      ),
      child: GestureDetector(
        onTap: enroll.isLoading ? null : () => enroll.confirm(savedP),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient:     context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow:    context.colors.primaryShadow,
          ),
          child: Center(
            child: enroll.isLoading
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(label,
                    style: const TextStyle(
                      color:      Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize:   16,
                      fontFamily: 'Cairo',
                    )),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — Bank transfer details
// ─────────────────────────────────────────────────────────────────────────────

class _BankStep extends StatelessWidget {
  const _BankStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final info   = enroll.bankInfo;
    final c      = context.colors;

    return Column(
      children: [
        ScreenAppBar(title: 'بيانات التحويل'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                // Top notice
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        c.primary.withValues(alpha: .08),
                        c.primary.withValues(alpha: .03),
                      ],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: c.primary.withValues(alpha: .2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: c.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'حوّل المبلغ المبيّن أدناه ثم اضغط "تم التحويل". سيتم مراجعة التحويل وتفعيل كورسك خلال 24 ساعة.',
                          style: c.body.copyWith(
                              color: c.primary, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Fee summary
                if (info != null) ...[
                  _BankTile(
                    label:     'المبلغ الإجمالي',
                    value:     '${info['fees']?['total']?.toStringAsFixed(2) ?? '—'} ر.س',
                    highlight: true,
                  ),
                  const SizedBox(height: 10),
                  _BankTile(
                    label:     'رقم المرجع (اكتبه في بيان التحويل)',
                    value:     info['instructions']['reference'] as String? ?? '—',
                    copyable:  true,
                    golden:    true,
                  ),
                  const SizedBox(height: 10),
                  _BankTile(label: 'اسم البنك',
                      value: info['instructions']['bank_name'] as String? ?? '—'),
                  const SizedBox(height: 10),
                  _BankTile(label: 'صاحب الحساب',
                      value:    info['instructions']['account_name'] as String? ?? '—',
                      copyable: true),
                  const SizedBox(height: 10),
                  _BankTile(label: 'رقم الحساب',
                      value:    info['instructions']['account_number'] as String? ?? '—',
                      copyable: true),
                  const SizedBox(height: 10),
                  _BankTile(label: 'الآيبان IBAN',
                      value:    info['instructions']['iban'] as String? ?? '—',
                      copyable: true,
                      mono:     true),
                  const SizedBox(height: 10),
                  _BankTile(label: 'SWIFT / BIC',
                      value:    info['instructions']['swift_code'] as String? ?? '—',
                      copyable: true,
                      mono:     true),
                ],

                const SizedBox(height: 28),

                // Confirm button
                GestureDetector(
                  onTap: context.read<EnrollmentProvider>().confirmBankTransfer,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient:     c.primaryGradient,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow:    c.primaryShadow,
                    ),
                    child: const Center(
                      child: Text('تم التحويل ✓',
                          style: TextStyle(
                            color:      Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize:   16,
                            fontFamily: 'Cairo',
                          )),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: context.read<EnrollmentProvider>().backToMethod,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color:        c.background,
                      borderRadius: BorderRadius.circular(30),
                      border:       Border.all(color: c.divider),
                    ),
                    child: Center(
                      child: Text('العودة',
                          style: c.label.copyWith(
                              color: c.textMedium)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BankTile extends StatefulWidget {
  final String label, value;
  final bool   copyable, highlight, golden, mono;
  const _BankTile({
    required this.label,
    required this.value,
    this.copyable  = false,
    this.highlight = false,
    this.golden    = false,
    this.mono      = false,
  });

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
    final bgColor = widget.golden
        ? Colors.amber.withValues(alpha: .07)
        : widget.highlight
            ? c.primary.withValues(alpha: .06)
            : c.cardBg;
    final borderColor = widget.golden
        ? Colors.amber.withValues(alpha: .35)
        : widget.highlight
            ? c.primary.withValues(alpha: .25)
            : c.divider;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: borderColor),
        boxShadow: widget.highlight || widget.golden ? [] : c.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: c.caption.copyWith(fontSize: 10)),
                const SizedBox(height: 4),
                Text(
                  widget.value,
                  style: widget.highlight
                      ? c.h2.copyWith(color: c.primary)
                      : widget.golden
                          ? c.h3.copyWith(
                              color:       Colors.amber[800],
                              letterSpacing: 1.4)
                          : c.label.copyWith(
                              fontWeight:  FontWeight.w600,
                              letterSpacing: widget.mono ? 1.5 : 0),
                ),
              ],
            ),
          ),
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
                  size:  16,
                  color: _copied ? c.success : c.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — Success
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessStep extends StatefulWidget {
  const _SuccessStep({super.key});

  @override
  State<_SuccessStep> createState() => _SuccessStepState();
}

class _SuccessStepState extends State<_SuccessStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale, _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.read<EnrollmentProvider>();
    final isPending = enroll.paidViaBankTransfer;
    final c = context.colors;

    final color1 = isPending ? c.accent : c.success;
    final color2 = isPending ? const Color(0xFFF39C12) : const Color(0xFF2ECC71);

    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Animated icon ──────────────────────────────────────────────
            ScaleTransition(
              scale: _scale,
              child: Center(
                child: Container(
                  width: 120, height: 120,
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [color1, color2],
                        begin:  Alignment.topLeft,
                        end:    Alignment.bottomRight),
                    boxShadow: [
                      BoxShadow(
                          color:      color1.withValues(alpha: .4),
                          blurRadius: 28,
                          offset:     const Offset(0, 10)),
                    ],
                  ),
                  child: Icon(
                    isPending
                        ? Icons.hourglass_top_rounded
                        : Icons.check_rounded,
                    color: Colors.white, size: 60,
                  ),
                ),
              ),
            ),

            Text(
              isPending ? 'في انتظار التحقق ⏳' : 'تم الاشتراك بنجاح! 🎉',
              style:     c.h1.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isPending
                  ? 'سيتم تفعيل الكورس خلال 24 ساعة بعد التحقق من التحويل البنكي.'
                  : 'يمكنك الوصول إلى كورسك الآن من قسم "كورساتي".',
              style:     c.body.copyWith(height: 1.7),
              textAlign: TextAlign.center,
            ),

            // Reference reminder
            if (isPending && enroll.bankInfo != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        Colors.amber.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: .35)),
                ),
                child: Column(
                  children: [
                    Text('رقم المرجع', style: c.caption),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          enroll.bankInfo!['instructions']['reference']
                                  as String? ??
                              '—',
                          style: c.h2.copyWith(
                              color:         Colors.amber[800],
                              letterSpacing: 1.5),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Clipboard.setData(ClipboardData(
                              text: enroll.bankInfo!['instructions']
                                  ['reference'] as String? ?? '')),
                          child: Icon(Icons.copy_rounded,
                              size: 18, color: Colors.amber[800]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),

            GestureDetector(
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient:     c.primaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow:    c.primaryShadow,
                ),
                child: Center(
                  child: Text(
                    isPending ? 'العودة للرئيسية' : 'ابدأ التعلم الآن',
                    style: const TextStyle(
                      color:      Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize:   16,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
