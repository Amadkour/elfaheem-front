/// enrollment_screen.dart — Premium redesign
///
/// Works on both Flutter Mobile and Flutter Web.
/// Mobile : full-screen with gradient hero header
/// Web    : centered card (max 560 px) with same premium design
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as helpers;
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../shared/payment/saved_methods_provider.dart';
import '../../shared/payment/saved_payment_models.dart';
import '../../shared/profile/course_instractor_profile.dart';
import '../../student/models.dart';
import 'enrollment_provider.dart';
import 'stc_otp_step.dart';

// ── Colours shared across this file ──────────────────────────────────────────

const _kStcColor    = Color(0xFF6A0DAD);
const _kBankColor   = Color(0xFF1B5E20);
const _kMadaColor   = Color(0xFF0D47A1);
const _kVisaColor   = Color(0xFF1A237E);
const _kMcColor     = Color(0xFFB71C1C);
const _kNewCardColor = Color(0xFF0F4C81);

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
      textDirection: helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Consumer<EnrollmentProvider>(
            builder: (_, enroll, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.03, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: switch (enroll.step) {
                EnrollStep.method     => const _MethodStep(key:    ValueKey('m')),
                EnrollStep.stcMobile  => const _StcMobileStep(key: ValueKey('sm')),
                EnrollStep.stcOtp     => const StcOtpStep(key:     ValueKey('so')),
                EnrollStep.bankDetails => const _BankStep(key:     ValueKey('b')),
                EnrollStep.verifying  => const _VerifyingStep(key: ValueKey('v')),
                EnrollStep.success    => const _SuccessStep(key:   ValueKey('ok')),
                EnrollStep.failed     => const _FailedStep(key:    ValueKey('f')),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Moyasar card payment screen (mobile) ──────────────────────────────────────

class MoyasarCardPaymentScreen extends StatelessWidget {
  final PaymentConfig config;
  final void Function(dynamic) onPaymentResult;
  const MoyasarCardPaymentScreen({
    super.key,
    required this.config,
    required this.onPaymentResult,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: helpers.pageDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text('بيانات البطاقة',
              style: TextStyle(fontFamily: 'bahji', color: c.textDark, fontWeight: FontWeight.w700)),
          backgroundColor: c.cardBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: c.textDark),
        ),
        backgroundColor: c.background,
        body: CreditCard(config: config, onPaymentResult: onPaymentResult),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 1 — Method picker
// ═════════════════════════════════════════════════════════════════════════════

class _MethodStep extends StatelessWidget {
  const _MethodStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final isWeb  = MediaQuery.of(context).size.width > 600;

    final body = Column(
      children: [
        ScreenAppBar(title: enroll.isFree ? 'تسجيل في الكورس' : 'إتمام الدفع'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(isWeb ? 32 : 20, 12, isWeb ? 32 : 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CourseSummaryCard(course: enroll.course),
                const SizedBox(height: 24),
                if (enroll.isFree)
                  const _FreeCourseBanner()
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

    if (!isWeb) return body;

    // Web: center in a max-width container
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: body,
      ),
    );
  }
}

// ── Course summary card ───────────────────────────────────────────────────────

class _CourseSummaryCard extends StatelessWidget {
  final CourseModel course;
  const _CourseSummaryCard({required this.course});

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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AppNetworkImage(
              url: course.imageUrl,
              width: 76,
              height: 76,
              heroTag: "course-enrollment-${course.id}",

            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name,
                    style: c.h3.copyWith(fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if(course.teacher!=Null)
                  InstructorAvatar(teacher: course.teacher!, size: 50, canOpen: true,),
                const SizedBox(height: 10),
                Row(children: [
                  _PriceBadge(price: course.price),
                  const SizedBox(width: 8),
                  _TypeTag(type: course.type),
                ]),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isFree
              ? [c.success.withValues(alpha: .15), c.success.withValues(alpha: .08)]
              : [c.primary.withValues(alpha: .15), c.primary.withValues(alpha: .06)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isFree ? c.success : c.primary).withValues(alpha: .3),
        ),
      ),
      child: Text(
        isFree ? 'مجاني' : '${price.toStringAsFixed(2)} ر.س',
        style: c.label.copyWith(
          color: isFree ? c.success : c.primary,
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
    final isLive = type == 'live';
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isLive ? c.danger : c.primary).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? '🔴 مباشر' : '▶ مسجّل',
        style: c.caption.copyWith(
          color: isLive ? c.danger : c.primary,
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
          colors: [c.success.withValues(alpha: .10), c.success.withValues(alpha: .04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.success.withValues(alpha: .3)),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: c.success.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.card_giftcard_rounded, color: c.success, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('هذا الكورس مجاني! 🎉',
                style: c.h3.copyWith(color: c.success)),
            const SizedBox(height: 4),
            Text('اضغط "سجّل الآن" للحصول على وصول فوري.',
                style: c.caption),
          ]),
        ),
      ]),
    );
  }
}

// ── Payment method picker ─────────────────────────────────────────────────────

class _SavedMethodPicker extends StatefulWidget {
  const _SavedMethodPicker();

  @override
  State<_SavedMethodPicker> createState() => _SavedMethodPickerState();
}

class _SavedMethodPickerState extends State<_SavedMethodPicker> {
  int _sel = -2; // -2=newCard, -1=bank, -3=stc, 0..n=saved card index

  Color _brandColor(CardBrand? b) => switch (b) {
    CardBrand.mada       => _kMadaColor,
    CardBrand.visa       => _kVisaColor,
    CardBrand.mastercard => _kMcColor,
    _                    => const Color(0xFF263238),
  };

  @override
  Widget build(BuildContext context) {
    final savedP  = context.watch<SavedMethodsProvider>();
    final enrollP = context.read<EnrollmentProvider>();
    final c       = context.colors;
    final cards   = savedP.cards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.primary, c.primary.withValues(alpha: .7)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payment_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text('طريقة الدفع', style: c.h3.copyWith(fontSize: 15)),
        ]),
        const SizedBox(height: 14),

        // Saved cards
        ...cards.asMap().entries.map((e) => _MethodTile(
          selected: _sel == e.key,
          icon: Icons.credit_card_rounded,
          iconColor: _brandColor(e.value.cardBrand),
          title: e.value.displayTitle,
          subtitle: '${e.value.cardBrand?.feeLabel ?? ''} رسوم المعالجة',
          badge: e.value.isDefault ? 'افتراضية' : null,
          onTap: () { if(mounted) setState(() => _sel = e.key); enrollP.selectSavedCard(e.value); },
        )),

        // STC Pay
        _MethodTile(
          selected: _sel == -3,
          icon: Icons.sim_card_rounded,
          iconColor: _kStcColor,
          title: 'STC Pay',
          subtitle: '2.5% + 1 ر.س رسوم',
          onTap: () { if(mounted) setState(() => _sel = -3); enrollP.selectStcPay(); },
          customBadge: _StcBadge(),
        ),

        // Bank transfer
        _MethodTile(
          selected: _sel == -1,
          icon: Icons.account_balance_rounded,
          iconColor: _kBankColor,
          title: 'تحويل بنكي',
          subtitle: 'بدون رسوم · مراجعة خلال 24 ساعة',
          onTap: () { if(mounted) setState(() => _sel = -1); enrollP.selectBankTransfer(); },
        ),

        // New card
        _MethodTile(
          selected: _sel == -2,
          icon: Icons.add_card_rounded,
          iconColor: _kNewCardColor,
          title: 'بطاقة ائتمانية / مدى جديدة',
          subtitle: 'مدى · فيزا · ماستركارد · PCI-DSS',
          onTap: () { if(mounted) setState(() => _sel = -2); enrollP.selectNewCard(); },
          customBadge: _SecureBadge(),
        ),
      ],
    );
  }
}

class _StcBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: _kStcColor.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _kStcColor.withValues(alpha: .3)),
    ),
    child: const Text('STC Pay',
        style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: _kStcColor, fontFamily: 'bahji',
        )),
  );
}

class _SecureBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_rounded, size: 9, color: Colors.green),
      const SizedBox(width: 3),
      Text('آمن', style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: Colors.green.shade700, fontFamily: 'bahji',
      )),
    ]),
  );
}

// ── Method tile ───────────────────────────────────────────────────────────────

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
          color: selected
              ? c.primary.withValues(alpha: .05)
              : c.cardBg,
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
            )
          ]
              : c.cardShadow,
        ),
        child: Row(children: [
          // Icon container
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? iconColor.withValues(alpha: .18)
                  : iconColor.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(title,
                      style: c.label.copyWith(
                        color: selected ? c.primary : c.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      )),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge!,
                        style: c.caption.copyWith(
                          color: Colors.amber.shade800, fontSize: 10,
                        )),
                  ),
                ],
                if (customBadge != null) ...[
                  const SizedBox(width: 6),
                  customBadge!,
                ],
              ]),
              const SizedBox(height: 3),
              Text(subtitle, style: c.caption.copyWith(fontSize: 11)),
            ]),
          ),

          // Radio indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.primary : Colors.transparent,
              border: Border.all(
                color: selected ? c.primary : c.divider,
                width: 2,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: c.primary.withValues(alpha: .3), blurRadius: 6)]
                  : [],
            ),
            child: selected
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ── Fee breakdown card ────────────────────────────────────────────────────────

class _FeeBreakdownCard extends StatefulWidget {
  const _FeeBreakdownCard();

  @override
  State<_FeeBreakdownCard> createState() => _FeeBreakdownCardState();
}

class _FeeBreakdownCardState extends State<_FeeBreakdownCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final savedP = context.watch<SavedMethodsProvider>();
    final fees   = enroll.computedFees(savedP);
    final c      = context.colors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        children: [
          // Header / toggle
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () { if(mounted) setState(() => _expanded = !_expanded);},
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: c.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('تفاصيل الفاتورة',
                    style: c.h3.copyWith(fontSize: 14))),
                // Total preview (always visible)
                Text(fees.fmt(fees.total),
                    style: c.h3.copyWith(color: c.primary, fontSize: 16)),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 250),
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: c.textLight, size: 22),
                ),
              ]),
            ),
          ),

          // Collapsible body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 260),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(children: [
                Divider(color: c.divider, height: 1),
                const SizedBox(height: 14),
                _FeeRow(label: 'سعر الكورس',
                    value: fees.fmt(fees.coursePrice),
                    icon: Icons.school_rounded),
                _FeeRow(label: 'رسوم المنصة (10%)',
                    value: fees.fmt(fees.platformFee),
                    icon: Icons.store_rounded),
                _FeeRow(label: 'ضريبة القيمة المضافة (15%)',
                    value: fees.fmt(fees.vatOnPlatform),
                    icon: Icons.receipt_rounded),
                _FeeRow(label: 'رسوم بوابة الدفع',
                    value: fees.fmt(fees.gatewayFee),
                    icon: Icons.credit_card_rounded,
                    sub: fees.gatewayLabel),
                const SizedBox(height: 10),
                Divider(color: c.divider, height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي', style: c.h2.copyWith(fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.primary, c.primary.withValues(alpha: .8)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(fees.fmt(fees.total),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            fontFamily: 'bahji',
                          )),
                    ),
                  ],
                ),
              ]),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final String? sub;
  const _FeeRow({required this.label, required this.value, required this.icon, this.sub});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 15, color: c.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: c.body.copyWith(fontSize: 13)),
            if (sub != null)
              Text(sub!, style: c.caption.copyWith(fontSize: 10)),
          ]),
        ),
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
    final fees   = enroll.isFree ? null : enroll.computedFees(savedP);
    final label  = enroll.isFree
        ? 'سجّل مجاناً الآن'
        : fees == null ? 'متابعة' : 'ادفع ${fees.fmt(fees.total)}';
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: c.cardBg,
        boxShadow: c.bottomNavShadow,
      ),
      child: GestureDetector(
        onTap: enroll.isLoading
            ? null
            : () => enroll.confirm(savedP, context),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: .35),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: enroll.isLoading
                ? const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
                : Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  fontFamily: 'bahji',
                )),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP — STC Mobile number entry
// ═════════════════════════════════════════════════════════════════════════════

class _StcMobileStep extends StatefulWidget {
  const _StcMobileStep({super.key});

  @override
  State<_StcMobileStep> createState() => _StcMobileStepState();
}

class _StcMobileStepState extends State<_StcMobileStep> {
  final _ctrl = TextEditingController();
  String? _err;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final m = _ctrl.text.trim();
    if (m.length < 9) { if(mounted) setState(() => _err = 'أدخل رقم جوال صحيح'); return; }
    if(mounted) setState(() => _err = null);
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

            // Brand circle
            Center(
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kStcColor, Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: _kStcColor.withValues(alpha: .4),
                    blurRadius: 22, offset: const Offset(0, 8),
                  )],
                ),
                child: const Icon(Icons.sim_card_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
            const SizedBox(height: 22),

            Text('أدخل رقم جوالك المسجّل في STC Pay',
                style: c.h2.copyWith(fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('سيصلك رمز تحقق SMS لإتمام الدفع.',
                style: c.body.copyWith(height: 1.7), textAlign: TextAlign.center),
            const SizedBox(height: 32),

            // Phone input
            Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _err != null ? c.danger : c.divider),
                boxShadow: c.cardShadow,
              ),
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: c.label.copyWith(fontSize: 18, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: '05XXXXXXXX',
                  hintStyle: c.caption,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 16),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.phone_android_rounded, color: _kStcColor),
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

            _GradientBtn(
              label: 'إرسال رمز التحقق',
              colors: [_kStcColor, const Color(0xFF9C27B0)],
              loading: enroll.isLoading,
              onTap: _submit,
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP — Bank transfer details
// ═════════════════════════════════════════════════════════════════════════════

class _BankStep extends StatelessWidget {
  const _BankStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollmentProvider>();
    final info   = enroll.bankInfo;
    final c      = context.colors;

    return Column(children: [
      ScreenAppBar(title: 'بيانات التحويل'),
      Expanded(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.primary.withValues(alpha: .2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: c.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'حوّل المبلغ مع ذكر رقم المرجع. سيتم تفعيل كورسك خلال 24 ساعة.',
                      style: c.body.copyWith(color: c.primary, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (info != null) ...[
              _BankTile(
                label: 'المبلغ',
                value: '${(info['fees']?['total'] as num?)?.toStringAsFixed(2) ?? '—'} ر.س',
                highlight: true,
              ),
              const SizedBox(height: 10),
              _BankTile(
                label: 'رقم المرجع',
                value: info['instructions']?['reference'] as String? ?? '—',
                copyable: true,
                golden: true,
              ),
              const SizedBox(height: 10),
              _BankTile(
                label: 'اسم البنك',
                value: info['instructions']?['bank_name'] as String? ?? '—',
              ),
              const SizedBox(height: 10),
              _BankTile(
                label: 'صاحب الحساب',
                value: info['instructions']?['account_name'] as String? ?? '—',
                copyable: true,
              ),
              const SizedBox(height: 10),
              _BankTile(
                label: 'الآيبان IBAN',
                value: info['instructions']?['iban'] as String? ?? '—',
                copyable: true,
                mono: true,
              ),
            ],

            const SizedBox(height: 28),
            _GradientBtn(
              label: 'تم التحويل ✓',
              onTap: enroll.confirmBankTransfer,
            ),
            const SizedBox(height: 12),
            _OutlineBtn(label: 'العودة', onTap: enroll.backToMethod),
          ]),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP — Verifying
// ═════════════════════════════════════════════════════════════════════════════

class _VerifyingStep extends StatelessWidget {
  const _VerifyingStep({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64, height: 64,
          child: CircularProgressIndicator(
            color: c.primary, strokeWidth: 3,
            backgroundColor: c.primaryTint,
          ),
        ),
        const SizedBox(height: 24),
        Text('جارٍ تأكيد الدفع…',
            style: c.h2.copyWith(fontSize: 18), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('الرجاء الانتظار قليلاً.',
            style: c.caption, textAlign: TextAlign.center),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP — Success
// ═════════════════════════════════════════════════════════════════════════════

class _SuccessStep extends StatefulWidget {
  const _SuccessStep({super.key});

  @override
  State<_SuccessStep> createState() => _SuccessStepState();
}

class _SuccessStepState extends State<_SuccessStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final enroll  = context.read<EnrollmentProvider>();
    final pending = enroll.paidViaBankTransfer;
    final c = context.colors;

    final Color col1 = pending ? c.accent  : c.success;
    final Color col2 = pending ? const Color(0xFFF39C12) : const Color(0xFF2ECC71);
    final IconData ico = pending ? Icons.hourglass_top_rounded : Icons.check_rounded;
    final String title = pending ? 'في انتظار التحقق ⏳' : 'تم الدفع بنجاح! 🎉';
    final String msg = pending
        ? 'سيتم تفعيل الكورس خلال 24 ساعة بعد التحقق من التحويل.'
        : 'تم تأكيد دفعتك وتفعيل الكورس. يمكنك البدء الآن!';

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
                  width: 120, height: 120,
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [col1, col2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(
                      color: col1.withValues(alpha: .45),
                      blurRadius: 32, offset: const Offset(0, 12),
                    )],
                  ),
                  child: Icon(ico, color: Colors.white, size: 60),
                ),
              ),
            ),
            Text(title, style: c.h1.copyWith(fontSize: 24), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(msg, style: c.body.copyWith(height: 1.8), textAlign: TextAlign.center),
            const SizedBox(height: 44),
            _GradientBtn(
              label: pending ? 'العودة للرئيسية' : 'ابدأ التعلم الآن',
              colors: [col1, col2],
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP — Failed
// ═════════════════════════════════════════════════════════════════════════════

class _FailedStep extends StatelessWidget {
  const _FailedStep({super.key});

  @override
  Widget build(BuildContext context) {
    final enroll = context.read<EnrollmentProvider>();
    final c = context.colors;
    final reason = enroll.failureReason ?? 'حدث خطأ. الرجاء المحاولة مرة أخرى.';
    final isSoft = reason.contains('قيد المعالجة') ||
        reason.contains('سيُفعَّل') ||
        reason.contains('تم الدفع');

    final Color col1 = isSoft ? c.accent  : c.danger;
    final Color col2 = isSoft ? const Color(0xFFF39C12) : const Color(0xFFE74C3C);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 110, height: 110,
              margin: const EdgeInsets.only(bottom: 28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [col1, col2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(
                  color: col1.withValues(alpha: .4),
                  blurRadius: 28, offset: const Offset(0, 10),
                )],
              ),
              child: Icon(
                isSoft ? Icons.hourglass_top_rounded : Icons.error_outline_rounded,
                color: Colors.white, size: 54,
              ),
            ),
          ),
          Text(isSoft ? 'الدفع قيد المعالجة' : 'فشلت عملية الدفع',
              style: c.h1.copyWith(fontSize: 22), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(reason, style: c.body.copyWith(height: 1.7), textAlign: TextAlign.center),
          const SizedBox(height: 40),
          _GradientBtn(
            label: isSoft ? 'العودة للرئيسية' : 'حاول مرة أخرى',
            colors: [col1, col2],
            onTap: isSoft
                ? () => Navigator.of(context).popUntil((r) => r.isFirst)
                : enroll.retryFromStart,
          ),
          const SizedBox(height: 14),
          _OutlineBtn(
            label: 'العودة للرئيسية',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

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
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.textDark, size: 20),
          onPressed: onBack,
        ),
        Expanded(
          child: Text(title,
              style: c.h2.copyWith(fontSize: 17), textAlign: TextAlign.center),
        ),
        const SizedBox(width: 44),
      ]),
    );
  }
}

class _GradientBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final List<Color>? colors;

  const _GradientBtn({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c  = context.colors;
    final g  = colors != null
        ? LinearGradient(colors: colors!, begin: Alignment.topLeft, end: Alignment.bottomRight)
        : c.primaryGradient;

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: g,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: (colors?.first ?? c.primary).withValues(alpha: .38),
              blurRadius: 18, offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFamily: 'bahji',
              )),
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: c.divider),
        ),
        child: Center(
          child: Text(label,
              style: c.label.copyWith(color: c.textMedium)),
        ),
      ),
    );
  }
}

// ── Bank detail tile ──────────────────────────────────────────────────────────

class _BankTile extends StatefulWidget {
  final String label, value;
  final bool copyable, highlight, golden, mono;
  const _BankTile({
    required this.label,
    required this.value,
    this.copyable = false,
    this.highlight = false,
    this.golden = false,
    this.mono = false,
  });

  @override
  State<_BankTile> createState() => _BankTileState();
}

class _BankTileState extends State<_BankTile> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    HapticFeedback.lightImpact();
    if(mounted) setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) if(mounted) setState(() => _copied = false);
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
            ? c.primary.withValues(alpha: .05)
            : c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.golden
              ? Colors.amber.withValues(alpha: .35)
              : widget.highlight
              ? c.primary.withValues(alpha: .25)
              : c.divider,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: c.caption.copyWith(fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              widget.value,
              style: widget.highlight
                  ? c.h2.copyWith(color: c.primary)
                  : widget.golden
                  ? c.h3.copyWith(color: Colors.amber.shade800, letterSpacing: 1.4)
                  : c.label.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: widget.mono ? 1.5 : 0),
            ),
          ]),
        ),
        if (widget.copyable)
          GestureDetector(
            onTap: _copy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _copied
                    ? c.success.withValues(alpha: .12)
                    : c.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
                color: _copied ? c.success : c.primary,
              ),
            ),
          ),
      ]),
    );
  }
}