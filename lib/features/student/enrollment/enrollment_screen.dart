import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import 'enrollment_provider.dart';

class EnrollmentScreen extends StatelessWidget {
  const EnrollmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
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
// STEP 1: Confirm / Method
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
                if (!isFree) ...[
                  const SizedBox(height: 24),
                  Text('طريقة الدفع', style: context.colors.h2),
                  const SizedBox(height: 14),
                  // ── Bank Transfer (only low-cost method) ──────────────────
                  _BankTransferMethodCard(),
                  const SizedBox(height: 12),
                  _BankTransferNote(),
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
        color:        context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow:    context.colors.cardShadow,
      ),
      child: Row(
        children: [
          AppNetworkImage(
            url:          course.imageUrl as String,
            width:        80,
            height:       80,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name as String,
                  style:    context.colors.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if ((course.teacherName as String?) != null &&
                    (course.teacherName as String).isNotEmpty)
                  Text(course.teacherName as String, style: context.colors.caption),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if ((course.rate as double?) != null) ...[
                      Icon(Icons.star_rounded,
                          color: context.colors.accent, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        (course.rate as double).toStringAsFixed(1),
                        style: context.colors.caption
                            .copyWith(color: context.colors.textDark),
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
          color:        context.colors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          border: Border.all(
            color: context.colors.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.card_giftcard_rounded,
                color: context.colors.success, size: 28),
            const SizedBox(width: 12),
            Text(
              'هذا الكورس مجاني تماماً!',
              style: context.colors.h3.copyWith(color: context.colors.success),
            ),
          ],
        ),
      );
    }

    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow:    context.colors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ملخص الطلب', style: context.colors.h3),
          const SizedBox(height: 14),
          Divider(color: context.colors.divider, height: 1),
          const SizedBox(height: 14),
          _PriceRow(
            label: 'سعر الكورس',
            value: '${provider.subtotal.toStringAsFixed(2)} ج.م',
          ),
          // No VAT — Egyptian educational services are VAT-exempt
          const SizedBox(height: 14),
          Divider(color: context.colors.divider, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: context.colors.h2),
              Text(
                '${provider.total.toStringAsFixed(2)} ج.م',
                style: context.colors.h2.copyWith(color: context.colors.primary),
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
        Text(label, style: context.colors.body.copyWith(height: 1)),
        Text(value,
            style: context.colors.label.copyWith(color: context.colors.textDark)),
      ],
    );
  }
}

// ── Bank Transfer Method Card (only payment option) ───────────────────────────

class _BankTransferMethodCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding:  const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        context.colors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        border: Border.all(color: context.colors.primary, width: 2),
        boxShadow:    context.colors.primaryShadow,
      ),
      child: Row(
        children: [
          Container(
            width:  46,
            height: 46,
            decoration: BoxDecoration(
              color:        context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.account_balance_rounded,
                size: 24, color: context.colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تحويل بنكي',
                  style: context.colors.label.copyWith(
                    color:      context.colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize:   14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'QNB — بنك قطر الوطني مصر',
                  style: context.colors.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            width:  22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primary,
              border: Border.all(color: context.colors.primary, width: 2),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }
}

// ── Bank Transfer Note ────────────────────────────────────────────────────────

class _BankTransferNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        context.colors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: context.colors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'سيتم تفعيل الكورس بعد التحقق من التحويل البنكي خلال 24 ساعة.',
              style: context.colors.caption.copyWith(
                color: context.colors.accent,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirm Bar ───────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  final EnrollmentProvider provider;

  const _ConfirmBar({required this.provider});

  String get _label {
    if (provider.isFree) return 'سجّل مجاناً';
    return 'متابعة للدفع — ${provider.total.toStringAsFixed(2)} ج.م';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color:     context.colors.cardBg,
        boxShadow: context.colors.bottomNavShadow,
      ),
      child: GestureDetector(
        onTap: !provider.isLoading ? () => provider.confirm() : null,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient:     context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow:    context.colors.primaryShadow,
          ),
          child: Center(
            child: provider.isLoading
                ? const SizedBox(
              width:  24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5,
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
                // ── Instruction banner ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:        context.colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(context.colors.radiusMedium),
                    border: Border.all(
                        color: context.colors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: context.colors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'حوّل المبلغ إلى الحساب أدناه ثم اضغط "تم التحويل". سيتم تفعيل الكورس بعد التحقق خلال 24 ساعة.',
                          style: context.colors.body.copyWith(
                              height: 1.6, color: context.colors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Amount ─────────────────────────────────────────────────
                _BankDetailTile(
                  label:     'المبلغ المطلوب',
                  value:     '${provider.total.toStringAsFixed(2)} ج.م',
                  highlight: true,
                ),
                const SizedBox(height: 12),

                if (info != null) ...[
                  // ── Reference (most important — used for verification) ──
                  _BankDetailTile(
                    label:    'رقم المرجع (اكتبه في بيان التحويل)',
                    value:    info.reference.isNotEmpty ? info.reference : '—',
                    copyable: true,
                    highlightBorder: true,
                  ),
                  const SizedBox(height: 12),

                  // ── Bank name ──────────────────────────────────────────
                  _BankDetailTile(
                    label:    'اسم البنك',
                    value:    info.bankName.isNotEmpty ? info.bankName : '—',
                    copyable: false,
                  ),
                  const SizedBox(height: 12),

                  // ── Account name ───────────────────────────────────────
                  _BankDetailTile(
                    label:    'اسم صاحب الحساب',
                    value:    info.accountName.isNotEmpty ? info.accountName : '—',
                    copyable: true,
                  ),
                  const SizedBox(height: 12),

                  // ── Account number ─────────────────────────────────────
                  _BankDetailTile(
                    label:    'رقم الحساب',
                    value:    info.accountNumber.isNotEmpty ? info.accountNumber : '—',
                    copyable: true,
                  ),
                  const SizedBox(height: 12),

                  // ── IBAN ───────────────────────────────────────────────
                  _BankDetailTile(
                    label:    'رقم الآيبان (IBAN)',
                    value:    info.iban.isNotEmpty ? info.iban : '—',
                    copyable: true,
                  ),
                  const SizedBox(height: 12),

                  // ── SWIFT ──────────────────────────────────────────────
                  _BankDetailTile(
                    label:    'كود السويفت (SWIFT / BIC)',
                    value:    info.swiftCode.isNotEmpty ? info.swiftCode : '—',
                    copyable: true,
                  ),
                ],
                const SizedBox(height: 32),

                // ── Confirm transfer button ────────────────────────────────
                GestureDetector(
                  onTap: provider.confirmBankTransfer,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient:     context.colors.primaryGradient,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow:    context.colors.primaryShadow,
                    ),
                    child: const Center(
                      child: Text(
                        'تم التحويل ✓',
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

                // ── Back button ────────────────────────────────────────────
                GestureDetector(
                  onTap: provider.backToMethod,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color:        context.colors.background,
                      borderRadius: BorderRadius.circular(30),
                      border:       Border.all(color: context.colors.divider),
                    ),
                    child: Center(
                      child: Text(
                        'العودة',
                        style: context.colors.label
                            .copyWith(color: context.colors.textMedium),
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
  final bool   highlightBorder;

  const _BankDetailTile({
    required this.label,
    required this.value,
    this.copyable       = false,
    this.highlight      = false,
    this.highlightBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlight
            ? context.colors.accent.withValues(alpha: 0.08)
            : context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        border: Border.all(
          color: highlight
              ? context.colors.accent.withValues(alpha: 0.3)
              : highlightBorder
              ? context.colors.primary.withValues(alpha: 0.4)
              : context.colors.divider,
          width: highlightBorder ? 1.5 : 1,
        ),
        boxShadow: highlight || highlightBorder ? [] : context.colors.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.colors.caption
                      .copyWith(color: context.colors.textMedium),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: highlight
                      ? context.colors.h2
                      .copyWith(color: context.colors.accent)
                      : context.colors.h3.copyWith(
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
                    backgroundColor: context.colors.success,
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
                  color:        context.colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.copy_rounded,
                    color: context.colors.primary, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3: Success / Pending Verification
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
    final provider = context.read<EnrollmentProvider>();
    final isPending = provider.paidViaBankTransfer; // bank transfer = pending

    // Colors & content differ between free enrollment and bank transfer
    final iconColor1 = isPending
        ? context.colors.accent
        : context.colors.success;
    final iconColor2 = isPending
        ? const Color(0xFFF39C12)
        : const Color(0xFF2ECC71);
    final icon = isPending ? Icons.hourglass_top_rounded : Icons.check_rounded;
    final headline = isPending
        ? 'في انتظار التحقق ⏳'
        : 'تم الاشتراك بنجاح! 🎉';
    final body = isPending
        ? 'تم إرسال طلب التسجيل في "${provider.course.name}". سيتم تفعيل الكورس خلال 24 ساعة بعد التحقق من التحويل البنكي.'
        : 'أنت الآن مسجّل في كورس "${provider.course.name}". يمكنك الوصول إليه من قسم "كورساتي".';
    final buttonLabel = isPending ? 'العودة للرئيسية' : 'الذهاب إلى كورساتي';

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
                  width:  120,
                  height: 120,
                  margin: const EdgeInsets.only(bottom: 32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape:    BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [iconColor1, iconColor2],
                      begin:  Alignment.topLeft,
                      end:    Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:      iconColor1.withValues(alpha: 0.40),
                        blurRadius: 28,
                        offset:     const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 60),
                ),
              ),
            ),

            Text(headline,
                style:     context.colors.h1.copyWith(fontSize: 26),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(body,
                style:     context.colors.body.copyWith(height: 1.7),
                textAlign: TextAlign.center),

            // ── Reference reminder for bank transfer ───────────────────────
            if (isPending && provider.bankInfo != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        context.colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: context.colors.accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('رقم المرجع الخاص بك',
                        style: context.colors.caption),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          provider.bankInfo!.reference,
                          style: context.colors.h2.copyWith(
                              color: context.colors.accent,
                              letterSpacing: 1.2),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Clipboard.setData(
                              ClipboardData(text: provider.bankInfo!.reference)),
                          child: Icon(Icons.copy_rounded,
                              size: 18, color: context.colors.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'احتفظ بهذا الرقم — سيُستخدم للتحقق من تحويلك',
                      style: context.colors.caption.copyWith(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),

            // ── Primary button ─────────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient:     context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow:    context.colors.primaryShadow,
                ),
                child: Center(
                  child: Text(
                    buttonLabel,
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
            const SizedBox(height: 14),

            // ── Secondary button ───────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color:        context.colors.background,
                  borderRadius: BorderRadius.circular(30),
                  border:       Border.all(color: context.colors.divider),
                ),
                child: Center(
                  child: Text(
                    'متابعة التصفح',
                    style: context.colors.label
                        .copyWith(color: context.colors.textMedium),
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
    final color  = isLive ? context.colors.danger : context.colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? '🔴 مباشر' : '▶ مسجّل',
        style: context.colors.caption.copyWith(
          color:      color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}