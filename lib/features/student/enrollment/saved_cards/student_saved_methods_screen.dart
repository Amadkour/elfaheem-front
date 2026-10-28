library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import 'saved_payment_models.dart';
import 'saved_methods_provider.dart';
import 'package:flutter_education_app/design/app_notice.dart';

class StudentSavedMethodsScreen extends StatelessWidget {
  const StudentSavedMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SavedMethodsProvider()..fetch(),
      child: const _StudentMethodsView(),
    );
  }
}

class _StudentMethodsView extends StatefulWidget {
  const _StudentMethodsView();

  @override
  State<_StudentMethodsView> createState() => _StudentMethodsViewState();
}

class _StudentMethodsViewState extends State<_StudentMethodsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'saved_payment_methods_title'.tr),
            // ── Tab bar ─────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              height: 46,
              decoration: BoxDecoration(
                color:        c.cardBg,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: c.divider),
              ),
              child: TabBar(
                controller: _tabs,
                indicator:  BoxDecoration(
                  gradient:     c.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorPadding: const EdgeInsets.all(3),
                labelColor:   context.colors.onHero,
                unselectedLabelColor: c.textMedium,
                labelStyle: const TextStyle(
                    fontFamily:  'bahji',
                    fontWeight:  FontWeight.w700,
                    fontSize:    13),
                tabs: [
                  Tab(text: 'my_cards_tab'.tr),
                  Tab(text: 'my_bank_accounts_tab'.tr),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _CardsTab(),
                  _BankAccountsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: Saved cards
// ─────────────────────────────────────────────────────────────────────────────

class _CardsTab extends StatelessWidget {
  const _CardsTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SavedMethodsProvider>();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Saved cards ──────────────────────────────────────────────────
          if (p.cards.isNotEmpty) ...[
            ...p.cards.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child:   _VisualCard(method: m),
            )),
            const SizedBox(height: 24),
          ],

          // ── Moyasar notice ───────────────────────────────────────────────
          _MoyasarNotice(),
          const SizedBox(height: 22),

          // ── "How to add card" (Moyasar handles card capture) ────────────
          _AddCardGuide(),
        ],
      ),
    );
  }
}

// ── Visual Card (premium animated bank card style) ────────────────────────────

class _VisualCard extends StatefulWidget {
  final SavedPaymentMethod method;
  const _VisualCard({required this.method});

  @override
  State<_VisualCard> createState() => _VisualCardState();
}

class _VisualCardState extends State<_VisualCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _anim = Tween<double>(begin: -2, end: 3)
        .animate(CurvedAnimation(parent: _shimmer, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.method;
    final p = context.read<SavedMethodsProvider>();
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => _buildCard(context, m, p),
    );
  }

  Widget _buildCard(
      BuildContext context, SavedPaymentMethod m, SavedMethodsProvider p) {
    final gradient = _brandGradient(m.cardBrand);
    return Stack(
      children: [
        // ── Card body ────────────────────────────────────────────────────
        AspectRatio(
          aspectRatio: 1.586,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient:     gradient,
              boxShadow: [
                BoxShadow(
                  color:      gradient.colors.first.withValues(alpha: .4),
                  blurRadius: 24,
                  offset:     const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  // Shimmer sweep
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(_anim.value - 0.8, -0.3),
                          end:   Alignment(_anim.value + 0.8,  0.3),
                          colors: [
                            Colors.transparent,
                            context.colors.onHero.withValues(alpha: .09),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Arc pattern
                  Positioned.fill(child: CustomPaint(painter: _ArcPainter(context.colors.onHero))),
                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Chip
                            _Chip(),
                            const Spacer(),
                            // Brand label
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:        context.colors.onHero.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                m.cardBrand?.label ?? 'card_label'.tr,
                                style: TextStyle(
                                  color:      context.colors.onHero,
                                  fontSize:   13,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'bahji',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Card number
                        Text(
                          '•••• •••• •••• ${m.cardLast4 ?? ''}',
                          style: TextStyle(
                            color:       context.colors.onHero,
                            fontSize:    20,
                            fontWeight:  FontWeight.w600,
                            letterSpacing: 3,
                            fontFamily:  'bahji',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'card_holder_label'.tr,
                                  style: TextStyle(
                                      color: context.colors.onHero.withValues(alpha: .5),
                                      fontSize: 9,
                                      fontFamily: 'bahji',
                                      letterSpacing: 1),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  m.cardHolderName ?? '—',
                                  style: TextStyle(
                                    color:      context.colors.onHero,
                                    fontSize:   12,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'bahji',
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'expires_label'.tr,
                                  style: TextStyle(
                                      color: context.colors.onHero.withValues(alpha: .5),
                                      fontSize: 9,
                                      fontFamily: 'bahji',
                                      letterSpacing: 1),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${m.cardExpiryMonth}/${m.cardExpiryYear?.substring(2) ?? ''}',
                                  style: TextStyle(
                                    color:      context.colors.onHero,
                                    fontSize:   13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'bahji',
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
        ),

        // ── Default badge ────────────────────────────────────────────────
        if (m.isDefault)
          Positioned(
            top: 10, left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        context.colors.cardBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 12, color: context.colors.warning),
                  const SizedBox(width: 4),
                  Text(
                    'default_card_badge'.tr,
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize:   11,
                        fontWeight: FontWeight.w700,
                        color: context.colors.warning),
                  ),
                ],
              ),
            ),
          ),

        // ── Action buttons overlay ────────────────────────────────────────
        Positioned(
          bottom: 8, right: 8,
          child: Row(
            children: [
              if (!m.isDefault)
                _CardAction(
                  icon:    Icons.star_border_rounded,
                  tooltip: 'default_card_badge'.tr,
                  onTap:   () => p.setDefault(m.id),
                ),
              const SizedBox(width: 6),
              _CardAction(
                icon:    Icons.delete_outline_rounded,
                tooltip: 'btn_delete'.tr,
                onTap:   () => _delete(context, p, m.id),
                danger:  true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  LinearGradient _brandGradient(CardBrand? brand) {
    switch (brand) {
      case CardBrand.mada:
        return const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        );
      case CardBrand.visa:
        return const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        );
      case CardBrand.mastercard:
        return const LinearGradient(
          colors: [Color(0xFF6D1A1A), Color(0xFFB71C1C)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        );
      case CardBrand.stcPay:
        return const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF263238), Color(0xFF37474F)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        );
    }
  }

  Future<void> _delete(
      BuildContext ctx, SavedMethodsProvider p, int id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title:   Text('delete_card_title'.tr, style: const TextStyle(fontFamily: 'bahji')),
        content: Text('delete_card_confirm'.tr, style: const TextStyle(fontFamily: 'bahji')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr, style: const TextStyle(fontFamily: 'bahji')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('btn_delete'.tr,
                style: TextStyle(
                    color: ctx.colors.danger, fontFamily: 'bahji')),
          ),
        ],
      ),
    );
    if (ok == true) await p.delete(id);
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String   tooltip;
  final VoidCallback onTap;
  final bool     danger;

  const _CardAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width:  34,
      height: 34,
      decoration: BoxDecoration(
        color:  context.colors.onHero.withValues(alpha: .9),
        shape:  BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: context.colors.heroShade.withValues(alpha: .15),
              blurRadius: 6),
        ],
      ),
      child: Icon(icon,
          size:  16,
          color: danger
              ? context.colors.danger
              : context.colors.primary),
    ),
  );
}

// ── Moyasar Notice ────────────────────────────────────────────────────────────

class _MoyasarNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        c.primaryTint,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: c.primary.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text('moyasar_secure_payment'.tr,
                  style: c.h3.copyWith(fontSize: 14, color: c.primary)),
            ],
          ),
          const SizedBox(height: 10),
          // Fee table
          _FeeRow(brand: 'brand_mada'.tr, fee: '1.9% + 1 ${'sar_currency'.tr}', isLowest: true),
          _FeeRow(brand: 'STC Pay',       fee: '2.5% + 1 ${'sar_currency'.tr}'),
          _FeeRow(brand: 'Visa / MC',     fee: '2.9% + 1 ${'sar_currency'.tr}'),
          _FeeRow(brand: 'Apple Pay',     fee: '2.9% + 1 ${'sar_currency'.tr}'),
          const SizedBox(height: 8),
          Text(
            'moyasar_card_save_notice'.tr,
            style: c.caption.copyWith(fontSize: 10, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String brand, fee;
  final bool   isLowest;

  const _FeeRow({
    required this.brand,
    required this.fee,
    this.isLowest = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Text('• $brand',
              style: c.caption.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 12)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color:        isLowest
                  ? c.success.withValues(alpha: .12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(fee,
                style: c.caption.copyWith(
                    color:  isLowest ? c.success : c.textMedium,
                    fontWeight: isLowest ? FontWeight.w700 : FontWeight.w400)),
          ),
          if (isLowest) ...[
            const SizedBox(width: 4),
            Text('fee_lowest'.tr, style: c.caption.copyWith(color: c.success, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

// ── Add Card Guide ────────────────────────────────────────────────────────────

class _AddCardGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
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
              Icon(Icons.add_card_rounded, color: c.primary, size: 22),
              const SizedBox(width: 8),
              Text('how_to_save_card'.tr, style: c.h3.copyWith(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          _Step(n: '1', text: 'save_card_step1'.tr),
          _Step(n: '2', text: 'save_card_step2'.tr),
          _Step(n: '3', text: 'save_card_step3'.tr),
          _Step(n: '4', text: 'save_card_step4'.tr),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n, text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width:  24,
            height: 24,
            decoration: BoxDecoration(
              color: c.primary, shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(n,
                  style: TextStyle(
                      color: c.onHero, fontSize: 11,
                      fontWeight: FontWeight.w800, fontFamily: 'bahji')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: c.body.copyWith(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: Bank accounts (student — for bank transfer payments)
// ─────────────────────────────────────────────────────────────────────────────

class _BankAccountsTab extends StatelessWidget {
  const _BankAccountsTab();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SavedMethodsProvider>();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.bankAccounts.isNotEmpty) ...[
            ...p.bankAccounts.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:   _StudentBankTile(method: m),
            )),
            const SizedBox(height: 24),
          ],
          _AddStudentBankForm(),
        ],
      ),
    );
  }
}

class _StudentBankTile extends StatelessWidget {
  final SavedPaymentMethod method;
  const _StudentBankTile({required this.method});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<SavedMethodsProvider>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow:    c.cardShadow,
        border: method.isDefault
            ? Border.all(color: c.primary, width: 1.5)
            : Border.all(color: c.divider),
      ),
      child: Row(
        children: [
          Container(
            width:  44,
            height: 44,
            decoration: BoxDecoration(
              color:        c.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.account_balance_rounded,
                color: c.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method.bankName ?? '—', style: c.h3.copyWith(fontSize: 14)),
                Text(
                  'IBAN •••• ${method.iban?.substring(method.iban!.length - 4) ?? ''}',
                  style: c.caption,
                ),
              ],
            ),
          ),
          if (method.isDefault)
            Icon(Icons.check_circle_rounded, color: c.primary, size: 20),
          if (!method.isDefault)
            TextButton(
              onPressed: () => p.setDefault(method.id),
              child: Text('default_label'.tr,
                  style: TextStyle(fontFamily: 'bahji', color: c.primary, fontSize: 12)),
            ),
          IconButton(
            tooltip: 'btn_delete'.tr,
            onPressed: () => p.delete(method.id),
            icon: Icon(Icons.close_rounded, size: 18, color: c.textLight),
          ),
        ],
      ),
    );
  }
}

class _AddStudentBankForm extends StatefulWidget {
  @override
  State<_AddStudentBankForm> createState() => _AddStudentBankFormState();
}

class _AddStudentBankFormState extends State<_AddStudentBankForm> {
  final _formKey  = GlobalKey<FormState>();
  final _bankCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  bool  _saving   = false;

  @override
  void dispose() {
    _bankCtrl.dispose(); _nameCtrl.dispose(); _ibanCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _saving = true);
    final p = context.read<SavedMethodsProvider>();
    final r = await p.saveBankAccount(
      bankName:    _bankCtrl.text.trim(),
      accountName: _nameCtrl.text.trim(),
      iban:        _ibanCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _saving = false);
      if (r != null) {
        _bankCtrl.clear(); _nameCtrl.clear(); _ibanCtrl.clear();
        showAppNotice('bank_account_saved_success'.tr);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        c.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow:    c.cardShadow,
        border:       Border.all(color: c.divider),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.add_rounded, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text('add_bank_account'.tr, style: c.h3.copyWith(fontSize: 14)),
            ]),
            const SizedBox(height: 16),
            MyTextField(
              controller: _bankCtrl,
              label: 'bank_name_label'.tr,
              validator: (v) => (v?.isEmpty ?? true) ? 'field_required'.tr : null,
            ),
            const SizedBox(height: 12),
            MyTextField(
              controller: _nameCtrl,
              label: 'account_holder_name'.tr,
              validator: (v) => (v?.isEmpty ?? true) ? 'field_required'.tr : null,
            ),
            const SizedBox(height: 12),
            MyTextField(
              controller: _ibanCtrl,
              label: 'iban_label'.tr,
              validator: (v) {
                if (v?.isEmpty ?? true) return 'field_required'.tr;
                if ((v?.trim().length ?? 0) < 15) return 'iban_too_short'.tr;
                return null;
              },
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label:     'save_account_btn'.tr,
              isLoading: _saving,
              onPressed: _save,
              icon: null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom painters ───────────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color       = ink.withValues(alpha: .05)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 60.0; r < 300; r += 45) {
      canvas.drawCircle(
          Offset(size.width * 1.1, size.height * 1.2), r, p);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.ink != ink;
}

class _Chip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width:  44,
    height: 34,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      gradient: const LinearGradient(
        colors: [Color(0xFFD4AF37), Color(0xFFF5C842)],
        begin:  Alignment.topLeft,
        end:    Alignment.bottomRight,
      ),
    ),
    child: CustomPaint(painter: _ChipPainter()),
  );
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color       = const Color(0xFFB8960C)
      ..strokeWidth = 0.8
      ..style       = PaintingStyle.stroke;
    final cx = size.width / 2, cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), p);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy),
            width: size.width * .5, height: size.height * .55),
        const Radius.circular(2),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}