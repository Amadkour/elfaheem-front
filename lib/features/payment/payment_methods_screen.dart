/// payment_methods_screen.dart
/// Premium payment & bank-info screen — refined fintech luxury aesthetic.
/// Responsive: mobile = stacked scroll, web ≥ 800 px = split layout.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/helpers.dart';
import 'payment_methods_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PaymentMethodsProvider()..fetchPayments(),
      child: const _PaymentMethodsView(),
    );
  }
}

// ── Main view ─────────────────────────────────────────────────────────────────

class _PaymentMethodsView extends StatelessWidget {
  const _PaymentMethodsView();

  static const _breakpoint = 800.0;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _breakpoint;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: isWide
              ? _WideLayout()
              : _NarrowLayout(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW (mobile) layout — stacked scroll
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScreenAppBar(title: 'طريقة الدفع'),
        Expanded(
          child: RefreshIndicator(
            color: context.colors.primary,
            onRefresh: () =>
                context.read<PaymentMethodsProvider>().fetchPayments(refresh: true),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _StatsRow(),
                  SizedBox(height: 28),
                  _BankCardHero(),
                  SizedBox(height: 28),
                  _BankDetailsSection(),
                  SizedBox(height: 32),
                  _PaymentHistorySection(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE (web/tablet) layout — split
// ─────────────────────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text('طريقة الدفع',
                  style: context.colors.h2.copyWith(fontSize: 17)),
              const Spacer(),
              _RefreshButton(),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left panel: bank card + details ─────────────────────────
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 24, 20, 40),
                  child: Column(
                    children: const [
                      _StatsRow(),
                      SizedBox(height: 28),
                      _BankCardHero(),
                      SizedBox(height: 28),
                      _BankDetailsSection(),
                    ],
                  ),
                ),
              ),

              // ── Divider ──────────────────────────────────────────────────
              VerticalDivider(
                  width: 1, thickness: 1, color: context.colors.divider),

              // ── Right panel: payment history ─────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  color: context.colors.primary,
                  onRefresh: () => context
                      .read<PaymentMethodsProvider>()
                      .fetchPayments(refresh: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
                    child: const _PaymentHistorySection(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PaymentMethodsProvider>();
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'إجمالي المدفوعات',
            value: '${p.totalPaid.toStringAsFixed(0)} ج.م',
            icon: Icons.payments_rounded,
            color: context.colors.success,
            bg: context.colors.success.withValues(alpha: .1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'قيد التحقق',
            value: '${p.pendingCount}',
            icon: Icons.hourglass_top_rounded,
            color: context.colors.accent,
            bg: context.colors.accent.withValues(alpha: .1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'مكتملة',
            value: '${p.completedCount}',
            icon: Icons.check_circle_rounded,
            color: context.colors.primary,
            bg: context.colors.primaryTint,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bg;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: context.colors.h2
                    .copyWith(color: color, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label,
                style: context.colors.caption.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED BANK CARD HERO
// ─────────────────────────────────────────────────────────────────────────────

class _BankCardHero extends StatefulWidget {
  const _BankCardHero();

  @override
  State<_BankCardHero> createState() => _BankCardHeroState();
}

class _BankCardHeroState extends State<_BankCardHero>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) => _CardFace(shimmerPos: _shimmer.value),
    );
  }
}

class _CardFace extends StatelessWidget {
  final double shimmerPos;
  const _CardFace({required this.shimmerPos});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586, // standard card ratio
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1628), Color(0xFF0D2856), Color(0xFF0A1A3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A1628).withValues(alpha: .55),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // ── Background geometric pattern ───────────────────────────
              Positioned.fill(child: CustomPaint(painter: _CardPatternPainter())),

              // ── Shimmer sweep ──────────────────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(shimmerPos - 0.8, -0.4),
                      end:   Alignment(shimmerPos + 0.8,  0.4),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: .07),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Content ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: chip + bank name
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // EMV chip
                        Container(
                          width: 44,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFD4AF37), Color(0xFFF5C842)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: CustomPaint(painter: _ChipPainter()),
                        ),
                        const Spacer(),
                        // QNB branding
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: .2)),
                              ),
                              child: const Text(
                                'QNB',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'بنك قطر الوطني',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .6),
                                fontSize: 9,
                                fontFamily: 'Cairo',
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const Spacer(),

                    // IBAN display (last segment highlighted)
                    Text(
                      'IBAN',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .45),
                        fontSize: 10,
                        letterSpacing: 2,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 4),
                    _IbanDisplay(),

                    const Spacer(),

                    // Bottom: account name + account number
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'صاحب الحساب',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .45),
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Ahmed Hamdy Madkour',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'رقم الحساب',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .45),
                                fontSize: 9,
                                letterSpacing: 1,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              PaymentMethodsProvider.accountNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
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
    );
  }
}

// Formats IBAN into groups: EG51 0037 0722 0840 1002 7021 6990 7
class _IbanDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const iban = PaymentMethodsProvider.iban;
    final groups = <String>[];
    for (var i = 0; i < iban.length; i += 4) {
      groups.add(iban.substring(i, math.min(i + 4, iban.length)));
    }
    return Wrap(
      spacing: 8,
      children: groups.asMap().entries.map((e) {
        final isLast = e.key == groups.length - 1;
        return Text(
          e.value,
          style: TextStyle(
            color: isLast
                ? const Color(0xFFD4AF37)
                : Colors.white.withValues(alpha: .85),
            fontSize: 13,
            fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 2,
            fontFamily: 'Cairo',
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BANK DETAILS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _BankDetailsSection extends StatelessWidget {
  const _BankDetailsSection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات التحويل البنكي',
                        style: c.h3.copyWith(fontSize: 14)),
                    Text('QNB — مصر',
                        style: c.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          // Fields
          _DetailRow(label: 'اسم البنك',    value: PaymentMethodsProvider.bankFullName,   copyable: false),
          _DetailRow(label: 'صاحب الحساب', value: PaymentMethodsProvider.accountName,    copyable: true),
          _DetailRow(label: 'رقم الحساب',  value: PaymentMethodsProvider.accountNumber,  copyable: true),
          _DetailRow(label: 'الآيبان IBAN', value: PaymentMethodsProvider.iban,           copyable: true),
          _DetailRow(label: 'SWIFT / BIC', value: PaymentMethodsProvider.swiftCode,      copyable: true, isLast: true),
        ],
      ),
    );
  }
}

class _DetailRow extends StatefulWidget {
  final String label, value;
  final bool copyable, isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.isLast   = false,
  });

  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: c.divider.withValues(alpha: .6))),
      ),
      child: Row(
        children: [
          // Left accent line
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Label + value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: c.caption.copyWith(fontSize: 10, letterSpacing: .5)),
                const SizedBox(height: 3),
                Text(
                  widget.value,
                  style: c.label.copyWith(
                    color: c.textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: widget.label.contains('IBAN') ||
                            widget.label.contains('SWIFT')
                        ? 1.5
                        : 0,
                  ),
                ),
              ],
            ),
          ),
          // Copy button
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
// PAYMENT HISTORY SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentHistorySection extends StatelessWidget {
  const _PaymentHistorySection();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PaymentMethodsProvider>();
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.primaryTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.history_rounded, size: 18, color: c.primary),
            ),
            const SizedBox(width: 10),
            Text('سجل المدفوعات',
                style: c.h2.copyWith(fontSize: 16)),
            const Spacer(),
            if (p.fetched)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${p.total}',
                  style: c.caption.copyWith(color: c.primary, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        if (p.isLoading && !p.fetched)
          const _HistorySkeleton()
        else if (p.payments.isEmpty)
          _EmptyHistory()
        else
          ListView.separated(
            shrinkWrap:  true,
            physics:     const NeverScrollableScrollPhysics(),
            itemCount:   p.payments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _PaymentTile(record: p.payments[i]),
          ),
      ],
    );
  }
}

// ── Single payment tile ───────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final PaymentRecord record;
  const _PaymentTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final c   = context.colors;
    final cfg = _statusConfig(context, record);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.cardShadow,
        border: Border.all(
          color: cfg.color.withValues(alpha: .12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Status icon circle
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cfg.color.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(cfg.icon, size: 22, color: cfg.color),
          ),
          const SizedBox(width: 14),

          // Course name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseName,
                  style: c.h3.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _MethodBadge(method: record.method),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(record.createdAt),
                      style: c.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Amount + status chip
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${record.amount.toStringAsFixed(0)} ج.م',
                style: c.h3.copyWith(
                  color: record.isCompleted ? c.success : c.textDark,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color:        cfg.color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  cfg.label,
                  style: c.caption.copyWith(
                    color:      cfg.color,
                    fontWeight: FontWeight.w700,
                    fontSize:   10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Status config ─────────────────────────────────────────────────────────────

class _StatusCfg {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusCfg(this.color, this.icon, this.label);
}

_StatusCfg _statusConfig(BuildContext context, PaymentRecord r) {
  final c = context.colors;
  if (r.isCompleted) return _StatusCfg(c.success,         Icons.check_circle_rounded,   'مكتمل');
  if (r.isPending)   return _StatusCfg(c.accent,           Icons.hourglass_top_rounded,  'قيد التحقق');
  if (r.isFailed)    return _StatusCfg(c.danger,           Icons.cancel_rounded,          'فشل');
  if (r.isRefunded)  return _StatusCfg(c.textMedium,       Icons.undo_rounded,            'مسترجع');
  return                     _StatusCfg(c.primary,          Icons.info_rounded,            r.status);
}

// ── Method badge ──────────────────────────────────────────────────────────────

class _MethodBadge extends StatelessWidget {
  final String method;
  const _MethodBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isBt = method == 'bank_transfer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color:        (isBt ? c.primary : c.accent).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isBt ? '🏦 تحويل' : '💳 بطاقة',
        style: c.caption.copyWith(
          fontSize:   10,
          color:      isBt ? c.primary : c.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color:        c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              color: c.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded, size: 34, color: c.primary),
          ),
          const SizedBox(height: 16),
          Text('لا توجد مدفوعات بعد',
              style: c.h3.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text('ستظهر هنا عند إتمام أول عملية دفع',
              style: c.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── Skeleton loader ───────────────────────────────────────────────────────────

class _HistorySkeleton extends StatefulWidget {
  const _HistorySkeleton();

  @override
  State<_HistorySkeleton> createState() => _HistorySkeletonState();
}

class _HistorySkeletonState extends State<_HistorySkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SkeletonTile(opacity: 1.0 - i * 0.15 - _anim.value * 0.2),
          ),
        ),
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  final double opacity;
  const _SkeletonTile({required this.opacity});

  @override
  Widget build(BuildContext context) {
    final base = context.colors.divider.withValues(alpha: opacity);
    return Container(
      height: 72,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        context.colors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: context.colors.divider),
      ),
      child: Row(
        children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 12, width: double.infinity, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 10, width: 120, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(height: 14, width: 60, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 6),
              Container(height: 20, width: 56, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(20))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Refresh button ────────────────────────────────────────────────────────────

class _RefreshButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PaymentMethodsProvider>();
    return GestureDetector(
      onTap: () => p.fetchPayments(refresh: true),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:        context.colors.primaryTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          p.isLoading ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
          size: 18, color: context.colors.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTERS
// ─────────────────────────────────────────────────────────────────────────────

/// Subtle radial arc pattern for the bank card background
class _CardPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Large arcs in bottom-right
    for (var r = 60.0; r <= 280; r += 40) {
      canvas.drawCircle(Offset(size.width * 1.1, size.height * 1.2), r, paint);
    }
    // Small cross-hatch in top-left
    for (var x = -10.0; x < size.width * 0.5; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.45), paint..strokeWidth = 0.5);
    }
    // Horizontal lines
    final hPaint = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 0.5;
    for (var y = 0.0; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// EMV chip grid lines
class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB8960C)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    // Horizontal
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    // Vertical
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    // Center rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy), width: size.width * .5, height: size.height * .55),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE FORMATTER (simple, no extra package)
// ─────────────────────────────────────────────────────────────────────────────

String _formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  } catch (_) {
    return iso.split('T').first;
  }
}
