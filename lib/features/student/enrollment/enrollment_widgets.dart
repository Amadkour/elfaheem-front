/// enrollment_widgets.dart — UI shared by the single-course and roadmap screens.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart' as helpers;
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'enrollment_models.dart';

bool isWideLayout(BuildContext context) => MediaQuery.of(context).size.width > 600;

/// Web / tablets: centred column, max 560 px. Mobile: full width.
class CenteredBody extends StatelessWidget {
  final Widget child;
  const CenteredBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) return child;
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child));
  }
}

void popToHome(BuildContext context) =>
    Navigator.of(context).popUntil((route) => route.isFirst);

// ── Buttons ───────────────────────────────────────────────────────────────────

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap; // null = disabled
  final bool loading;
  final List<Color>? colors;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null && !loading;
    final gradient = colors != null
        ? LinearGradient(colors: colors!, begin: Alignment.topLeft, end: Alignment.bottomRight)
        : c.primaryGradient;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: (colors?.first ?? c.primary).withValues(alpha: .38),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(width: 22, height: 22, child: AppLoadingIndicator())
                : Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFamily: 'bahji',
                )),
          ),
        ),
      ),
    );
  }
}

class SoftOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const SoftOutlineButton({super.key, required this.label, required this.onTap});

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
        child: Center(child: Text(label, style: c.label.copyWith(color: c.textMedium))),
      ),
    );
  }
}

/// Sticky bottom bar with the main action.
class EnrollConfirmBar extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const EnrollConfirmBar({super.key, required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(color: c.cardBg, boxShadow: c.bottomNavShadow),
      child: GradientButton(label: label, onTap: onTap, loading: loading),
    );
  }
}

// ── Fee breakdown ─────────────────────────────────────────────────────────────

class FeeBreakdownCard extends StatefulWidget {
  final FeeQuote? quote; // null while loading
  final String currencySymbol;
  const FeeBreakdownCard({super.key, required this.quote, required this.currencySymbol});

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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: q == null ? null : () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_long_rounded, color: c.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('billing_details'.tr, style: c.h3.copyWith(fontSize: 14))),
              if (q == null)
                const SizedBox(width: 20, height: 20, child: AppLoadingIndicator())
              else ...[
                Text('${q.fmt(q.total)} $symbol',
                    style: c.h3.copyWith(color: c.primary, fontSize: 16)),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 250),
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: c.textLight, size: 22),
                ),
              ],
            ]),
          ),
        ),
        if (q != null)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 260),
            crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            secondChild: const SizedBox.shrink(),
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(children: [
                Divider(color: c.divider, height: 1),
                const SizedBox(height: 14),
                _FeeRow(label: 'course_price'.tr, value: q.fmt(q.coursePrice), icon: Icons.school_rounded),
                _FeeRow(label: 'platform_fees'.tr, value: q.fmt(q.platformFee), icon: Icons.store_rounded),
                _FeeRow(label: 'VAT', value: q.fmt(q.vatOnPlatform), icon: Icons.receipt_rounded),
                _FeeRow(
                  label: 'gateway_fees'.tr,
                  value: q.fmt(q.gatewayFee),
                  icon: Icons.credit_card_rounded,
                  sub: q.gatewayLabel,
                ),
                const SizedBox(height: 10),
                Divider(color: c.divider, height: 1),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('الإجمالي', style: c.h2.copyWith(fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c.primary, c.primary.withValues(alpha: .8)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${q.fmt(q.total)} $symbol',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          fontFamily: 'bahji',
                        )),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
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
            if (sub != null && sub!.isNotEmpty) Text(sub!, style: c.caption.copyWith(fontSize: 10)),
          ]),
        ),
        Text(value, style: c.label.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Result screens ────────────────────────────────────────────────────────────

class PaymentVerifyingView extends StatelessWidget {
  const PaymentVerifyingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 64, height: 64, child: AppLoadingIndicator()),
        const SizedBox(height: 24),
        Text('جارٍ تأكيد الدفع…', style: c.h2.copyWith(fontSize: 18), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('الرجاء الانتظار قليلاً.', style: c.caption, textAlign: TextAlign.center),
      ]),
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

class _PaymentResultViewState extends State<PaymentResultView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
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
    final c = context.colors;
    final (Color c1, Color c2, IconData icon) = switch (widget.kind) {
      ResultKind.success => (c.success, const Color(0xFF2ECC71), Icons.check_rounded),
      ResultKind.pending => (c.accent, const Color(0xFFF39C12), Icons.hourglass_top_rounded),
      ResultKind.failed => (c.danger, const Color(0xFFE74C3C), Icons.error_outline_rounded),
    };

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
                        colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [
                      BoxShadow(color: c1.withValues(alpha: .45), blurRadius: 32, offset: const Offset(0, 12))
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 60),
                ),
              ),
            ),
            Text(widget.title, style: c.h1.copyWith(fontSize: 24), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(widget.message, style: c.body.copyWith(height: 1.8), textAlign: TextAlign.center),
            const SizedBox(height: 44),
            GradientButton(label: widget.primaryLabel, colors: [c1, c2], onTap: widget.onPrimary),
            if (widget.secondaryLabel != null && widget.onSecondary != null) ...[
              const SizedBox(height: 14),
              SoftOutlineButton(label: widget.secondaryLabel!, onTap: widget.onSecondary!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Copy for the three result kinds, shared so both flows say the same thing.
class ResultCopy {
  static const pendingTitle = 'الدفع قيد المعالجة ⏳';
  static const pendingMessage = 'تم استلام طلبك. سيُفعَّل كورسك تلقائياً خلال دقائق.';

  // Shown instead of the pair above when the student already has a manual
  // transfer (bank/InstaPay) proof awaiting teacher review for this course —
  // see EnrollmentProvider.pendingIsManualReview.
  static const pendingReviewTitle = 'طلبك قيد المراجعة ⏳';
  static const pendingReviewMessage =
      'لديك طلب دفع (تحويل بنكي / إنستاباي) قيد المراجعة حالياً. '
      'سيقوم المعلم بمراجعته وسيتم تفعيل الكورس أو إشعارك فور الرد.';

  static const failedTitle = 'فشلت عملية الدفع';
  static const failedFallback = 'حدث خطأ. الرجاء المحاولة مرة أخرى.';
}

/// Thin scaffold used by both screens so direction + background match.
class EnrollScaffold extends StatelessWidget {
  final Widget child;
  const EnrollScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(.03, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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