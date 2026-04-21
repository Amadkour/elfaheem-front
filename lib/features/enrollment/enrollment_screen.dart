/// ─────────────────────────────────────────────────────────────────────────────
/// enrollment_screen.dart
/// Full enrollment flow for a single course.
///
/// Steps:
///   1. EnrollStep.method      — course summary + payment method selection
///   2. EnrollStep.bankDetails — IBAN / account details after bank-transfer init
///   3. EnrollStep.success     — animated success confirmation
///
/// State: [EnrollmentProvider]
///
/// Usage:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => ChangeNotifierProvider(
///       create: (_) => EnrollmentProvider(course),
///       child: const EnrollmentScreen(),
///     ),
///   ));
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart' as Helpers;
import '../../config/app_theme.dart';
import '../../utils/widget/app_network_image.dart';
import '../../utils/widget/app_bar.dart';
import 'enrollment_provider.dart';

class EnrollmentScreen extends StatelessWidget {
  const EnrollmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Consumer<EnrollmentProvider>(
            builder: (context, provider, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end:   Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: switch (provider.step) {
                  EnrollStep.method      => const _MethodStep(key: ValueKey('method')),
                  EnrollStep.bankDetails => const _BankStep(key: ValueKey('bank')),
                  EnrollStep.success     => const _SuccessStep(key: ValueKey('success')),
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1: Method Selection
// ─────────────────────────────────────────────────────────────────────────────

class _MethodStep extends StatelessWidget {
  const _MethodStep({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EnrollmentProvider>();
    final isFree   = provider.isFree;

    return Column(
      children: [
        ScreenAppBar(title: isFree ? 'تسجيل في الكورس' : 'الدفع والاشتراك'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CourseSummaryCard(course: provider.course),
                const SizedBox(height: 24),
                _PriceBreakdown(provider: provider),
                const SizedBox(height: 24),
                if (!isFree) ...[
                  Text('طريقة الدفع', style: AppTheme.h2),
                  const SizedBox(height: 14),
                  _PaymentMethodCard(
                    method:   PaymentMethod.mada,
                    icon:     Icons.credit_card_rounded,
                    selected: provider.selectedMethod == PaymentMethod.mada,
                    onTap:    () => provider.selectMethod(PaymentMethod.mada),
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method:   PaymentMethod.visa,
                    icon:     Icons.payment_rounded,
                    selected: provider.selectedMethod == PaymentMethod.visa,
                    onTap:    () => provider.selectMethod(PaymentMethod.visa),
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method:   PaymentMethod.bankTransfer,
                    icon:     Icons.account_balance_rounded,
                    selected: provider.selectedMethod == PaymentMethod.bankTransfer,
                    onTap:    () =>
                        provider.selectMethod(PaymentMethod.bankTransfer),
                  ),
                  const SizedBox(height: 8),
                  _SecureNote(),
                ],
              ],
            ),
          ),
        ),
        _ConfirmBar(provider: provider),
      ],
    );
  }
}

// ── Course Summary Card ───────────────────────────────────────────────────────

class _CourseSummaryCard extends StatelessWidget {
  final dynamic course; // CourseModel

  const _CourseSummaryCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow:    AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          // Thumbnail
          AppNetworkImage(
            url:          course.imageUrl as String,
            width:        80,
            height:       80,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name as String,
                  style:    AppTheme.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if ((course.teacherName as String?) != null &&
                    (course.teacherName as String).isNotEmpty)
                  Text(course.teacherName as String, style: AppTheme.caption),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if ((course.rate as double?) != null) ...[
                      const Icon(Icons.star_rounded,
                          color: AppTheme.accent, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        (course.rate as double).toStringAsFixed(1),
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textDark),
                      ),
                      const SizedBox(width: 10),
                    ],
                    _TypeBadge(type: course.type as String),
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

// ── Price Breakdown ───────────────────────────────────────────────────────────

class _PriceBreakdown extends StatelessWidget {
  final EnrollmentProvider provider;

  const _PriceBreakdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isFree) {
      return Container(
        padding:    const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard_rounded,
                color: AppTheme.success, size: 28),
            const SizedBox(width: 12),
            Text(
              'هذا الكورس مجاني تماماً!',
              style: AppTheme.h3.copyWith(color: AppTheme.success),
            ),
          ],
        ),
      );
    }

    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow:    AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ملخص الطلب', style: AppTheme.h3),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 14),
          _PriceRow(label: 'سعر الكورس',
              value: '\$ ${provider.subtotal.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _PriceRow(label: 'ضريبة القيمة المضافة (15%)',
              value: '\$ ${provider.vat.toStringAsFixed(2)}'),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: AppTheme.h2),
              Text(
                '\$ ${provider.total.toStringAsFixed(2)}',
                style: AppTheme.h2.copyWith(color: AppTheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;

  const _PriceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.body.copyWith(height: 1)),
        Text(value, style: AppTheme.label.copyWith(color: AppTheme.textDark)),
      ],
    );
  }
}

// ── Payment Method Card ───────────────────────────────────────────────────────

class _PaymentMethodCard extends StatelessWidget {
  final PaymentMethod method;
  final IconData      icon;
  final bool          selected;
  final VoidCallback  onTap;

  const _PaymentMethodCard({
    required this.method,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding:  const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        selected
              ? AppTheme.primary.withValues(alpha: 0.07)
              : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected ? AppTheme.primaryShadow : AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            // Icon container
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width:  46,
              height: 46,
              decoration: BoxDecoration(
                color:        selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : AppTheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size:  24,
                color: selected ? AppTheme.primary : AppTheme.textMedium,
              ),
            ),
            const SizedBox(width: 14),
            // Label
            Expanded(
              child: Text(
                method.label,
                style: AppTheme.label.copyWith(
                  color:      selected ? AppTheme.primary : AppTheme.textDark,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize:   14,
                ),
              ),
            ),
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width:  22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.textLight,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Secure Note ───────────────────────────────────────────────────────────────

class _SecureNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_rounded, size: 14, color: AppTheme.textLight),
        const SizedBox(width: 6),
        Text(
          'الدفع آمن ومشفر بالكامل',
          style: AppTheme.caption.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

// ── Confirm Bar ───────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  final EnrollmentProvider provider;

  const _ConfirmBar({required this.provider});

  bool get _canConfirm =>
      provider.isFree || provider.selectedMethod != null;

  String get _label {
    if (provider.isFree) return 'سجّل مجاناً';
    return provider.selectedMethod == null
        ? 'اختر طريقة الدفع'
        : 'تأكيد الاشتراك — \$ ${provider.total.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color:     AppTheme.cardBg,
        boxShadow: AppTheme.bottomNavShadow,
      ),
      child: AnimatedOpacity(
        opacity:  _canConfirm ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _canConfirm && !provider.isLoading
              ? () => provider.confirm()
              : null,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient:     AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow:    _canConfirm ? AppTheme.primaryShadow : [],
            ),
            child: Center(
              child: provider.isLoading
                  ? const SizedBox(
                      width:  24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color:       Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      _label,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2: Bank Transfer Details
// ─────────────────────────────────────────────────────────────────────────────

class _BankStep extends StatelessWidget {
  const _BankStep({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EnrollmentProvider>();
    final info     = provider.bankInfo;

    return Column(
      children: [
        ScreenAppBar(title: 'بيانات التحويل البنكي'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Instruction banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:        AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppTheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'يرجى تحويل المبلغ إلى الحساب أدناه، ثم الضغط على "تم التحويل". سيتم تفعيل الكورس بعد التحقق من التحويل.',
                          style: AppTheme.body.copyWith(
                              height: 1.6, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Amount due
                _BankDetailTile(
                  label: 'المبلغ المطلوب',
                  value: '\$ ${provider.total.toStringAsFixed(2)}',
                  highlight: true,
                ),
                const SizedBox(height: 12),
                if (info != null) ...[
                  _BankDetailTile(
                    label:     'اسم البنك',
                    value:     info.bankName.isNotEmpty ? info.bankName : '—',
                    copyable:  false,
                  ),
                  const SizedBox(height: 12),
                  _BankDetailTile(
                    label:    'رقم الحساب',
                    value:    info.accountNumber.isNotEmpty
                        ? info.accountNumber
                        : '—',
                    copyable: true,
                  ),
                  const SizedBox(height: 12),
                  _BankDetailTile(
                    label:    'رقم الآيبان (IBAN)',
                    value:    info.iban.isNotEmpty ? info.iban : '—',
                    copyable: true,
                  ),
                ],
                const SizedBox(height: 32),
                // Confirm transfer button
                GestureDetector(
                  onTap: provider.confirmBankTransfer,
                  child: Container(
                    height:     54,
                    decoration: BoxDecoration(
                      gradient:     AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow:    AppTheme.primaryShadow,
                    ),
                    child: const Center(
                      child: Text(
                        'تم التحويل',
                        style: TextStyle(
                          color:      Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize:   16,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Back button
                GestureDetector(
                  onTap: provider.backToMethod,
                  child: Container(
                    height:     48,
                    decoration: BoxDecoration(
                      color:        AppTheme.background,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Center(
                      child: Text(
                        'العودة لاختيار طريقة الدفع',
                        style: AppTheme.label.copyWith(
                            color: AppTheme.textMedium),
                      ),
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

// ── Bank Detail Tile ──────────────────────────────────────────────────────────

class _BankDetailTile extends StatelessWidget {
  final String label;
  final String value;
  final bool   copyable;
  final bool   highlight;

  const _BankDetailTile({
    required this.label,
    required this.value,
    this.copyable  = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        highlight
            ? AppTheme.accent.withValues(alpha: 0.08)
            : AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border:       Border.all(
          color: highlight
              ? AppTheme.accent.withValues(alpha: 0.3)
              : AppTheme.divider,
        ),
        boxShadow: highlight ? [] : AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textMedium)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: highlight
                      ? AppTheme.h2.copyWith(color: AppTheme.accent)
                      : AppTheme.h3.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                ),
              ],
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم النسخ: $value',
                        style: const TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: AppTheme.success,
                    behavior:        SnackBarBehavior.floating,
                    duration:        const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.copy_rounded,
                    color: AppTheme.primary, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3: Success
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessStep extends StatefulWidget {
  const _SuccessStep({super.key});

  @override
  State<_SuccessStep> createState() => _SuccessStepState();
}

class _SuccessStepState extends State<_SuccessStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    )..forward();
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
    final course = context.read<EnrollmentProvider>().course;

    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success icon
            ScaleTransition(
              scale: _scale,
              child: Container(
                width:  120,
                height: 120,
                margin: const EdgeInsets.only(bottom: 32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape:     BoxShape.circle,
                  gradient:  const LinearGradient(
                    colors: [AppTheme.success, Color(0xFF2ECC71)],
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      AppTheme.success.withValues(alpha: 0.40),
                      blurRadius: 28,
                      offset:     const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 60),
              ),
            ),
            Text(
              'تم الاشتراك بنجاح! 🎉',
              style:     AppTheme.h1.copyWith(fontSize: 26),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'أنت الآن مسجّل في كورس "${course.name}". يمكنك الوصول إليه من قسم "كورساتي".',
              style:     AppTheme.body.copyWith(height: 1.7),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Go to my courses
            GestureDetector(
              onTap: () {
                // Pop until the courses screen or the navigator root
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: Container(
                height:     54,
                decoration: BoxDecoration(
                  gradient:     AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow:    AppTheme.primaryShadow,
                ),
                child: const Center(
                  child: Text(
                    'الذهاب إلى كورساتي',
                    style: TextStyle(
                      color:      Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize:   16,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Continue browsing
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height:     48,
                decoration: BoxDecoration(
                  color:        AppTheme.background,
                  borderRadius: BorderRadius.circular(30),
                  border:       Border.all(color: AppTheme.divider),
                ),
                child: Center(
                  child: Text(
                    'متابعة التصفح',
                    style: AppTheme.label.copyWith(color: AppTheme.textMedium),
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

// ── Helpers ───────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    final color  = isLive ? AppTheme.danger : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? '🔴 مباشر' : '▶ مسجّل',
        style: AppTheme.caption.copyWith(
          color:      color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
