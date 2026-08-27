// teacher_payout_screen.dart
/// Teacher manages bank accounts for receiving course revenue payouts.
/// Premium design: deep emerald + gold fintech aesthetic, animated hero card.
library;


import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/text_field.dart';
import '../../../utils/widget/primary_button.dart';
import 'saved_payment_models.dart';
import 'saved_methods_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class TeacherPayoutScreen extends StatelessWidget {
  const TeacherPayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SavedMethodsProvider()..fetch(),
      child: const _TeacherPayoutView(),
    );
  }
}

class _TeacherPayoutView extends StatelessWidget {
  const _TeacherPayoutView();

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'payout_accounts_title'.tr),
            Expanded(
              child: Consumer<SavedMethodsProvider>(
                builder: (context, p, _) {
                  if (p.isLoading && !p.fetched) {
                    return const Center(child: AppLoadingIndicator());
                  }
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Info banner ──────────────────────────────────
                        _InfoBanner(),
                        const SizedBox(height: 24),

                        // ── Saved bank accounts ──────────────────────────
                        if (p.bankAccounts.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'your_bank_accounts'.tr,
                            icon: Icons.account_balance_rounded,
                          ),
                          const SizedBox(height: 14),
                          ...p.bankAccounts.map(
                                (m) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _BankAccountCard(method: m),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Add new ──────────────────────────────────────
                        _SectionHeader(
                          title: p.bankAccounts.isEmpty
                              ? 'add_your_bank_account'.tr
                              : 'add_new_account'.tr,
                          icon: Icons.add_card_rounded,
                        ),
                        const SizedBox(height: 16),
                        const _AddBankForm(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info Banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4332).withValues(alpha: .35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'payout_system_label'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFamily: 'bahji',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'payout_system_desc'.tr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .8),
                    fontSize: 11,
                    fontFamily: 'bahji',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.primaryTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: c.primary),
        ),
        const SizedBox(width: 10),
        Text(title, style: c.h3.copyWith(fontSize: 15)),
      ],
    );
  }
}

// ── Saved Bank Account Card ───────────────────────────────────────────────────

class _BankAccountCard extends StatelessWidget {
  final SavedPaymentMethod method;

  const _BankAccountCard({required this.method});

  @override
  Widget build(BuildContext context) {
    final p = context.read<SavedMethodsProvider>();
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.cardShadow,
        border: method.isDefault
            ? Border.all(color: const Color(0xFF2D6A4F), width: 2)
            : Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          // ── Card header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: method.isDefault
                  ? const Color(0xFF1B4332).withValues(alpha: .06)
                  : Colors.transparent,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_rounded,
                      color: Color(0xFF2D6A4F), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.bankName ?? '—',
                        style: c.h3.copyWith(fontSize: 14),
                      ),
                      Text(
                        method.accountName ?? '',
                        style: c.caption,
                      ),
                    ],
                  ),
                ),
                if (method.isDefault)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'default_label'.tr,
                      style: const TextStyle(
                        color: Color(0xFF2D6A4F),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'bahji',
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Divider(height: 1, color: c.divider),

          // ── IBAN row ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IBAN', style: c.caption.copyWith(fontSize: 10)),
                      const SizedBox(height: 3),
                      Text(
                        _fmtIban(method.iban),
                        style: c.label.copyWith(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions
                if (!method.isDefault)
                  TextButton.icon(
                    onPressed: () => p.setDefault(method.id),
                    icon: const Icon(Icons.star_border_rounded, size: 16),
                    label: Text('default_label'.tr,
                        style: const TextStyle(fontFamily: 'bahji', fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: c.primary),
                  ),
                IconButton(
                  onPressed: () => _confirmDelete(context, p, method.id),
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 20, color: c.danger),
                  tooltip: 'btn_delete'.tr,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtIban(String? iban) {
    if (iban == null || iban.isEmpty) return '—';
    final clean = iban.replaceAll(' ', '');
    final buf = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(clean[i]);
    }
    return buf.toString();
  }

  Future<void> _confirmDelete(
      BuildContext context, SavedMethodsProvider p, int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('delete_account_title'.tr, style: const TextStyle(fontFamily: 'bahji')),
        content: Text('delete_account_confirm'.tr, style: const TextStyle(fontFamily: 'bahji')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr, style: const TextStyle(fontFamily: 'bahji')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('btn_delete'.tr,
                style: TextStyle(
                    color: context.colors.danger, fontFamily: 'bahji')),
          ),
        ],
      ),
    );
    if (ok == true) await p.delete(id);
  }
}

// ── Add Bank Form ─────────────────────────────────────────────────────────────

class _AddBankForm extends StatefulWidget {
  const _AddBankForm();

  @override
  State<_AddBankForm> createState() => _AddBankFormState();
}

class _AddBankFormState extends State<_AddBankForm> {
  final _formKey = GlobalKey<FormState>();
  final _bankCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _swiftCtrl = TextEditingController();
  bool _setAsDefault = true;
  bool _saving = false;

  @override
  void dispose() {
    _bankCtrl.dispose();
    _nameCtrl.dispose();
    _ibanCtrl.dispose();
    _swiftCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() => _saving = true);
    final p = context.read<SavedMethodsProvider>();
    final result = await p.saveBankAccount(
      bankName: _bankCtrl.text.trim(),
      accountName: _nameCtrl.text.trim(),
      iban: _ibanCtrl.text.trim(),
      swiftCode:
      _swiftCtrl.text.trim().isNotEmpty ? _swiftCtrl.text.trim() : null,
      setAsDefault: _setAsDefault,
    );
    if (mounted) {
      setState(() => _saving = false);
      if (result != null) {
        _bankCtrl.clear();
        _nameCtrl.clear();
        _ibanCtrl.clear();
        _swiftCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          _snack('bank_account_saved_success'.tr, context.colors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          _snack(p.errorMessage ?? 'error_occurred'.tr, context.colors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyTextField(
              controller: _bankCtrl,
              label: 'bank_name_label'.tr,
              validator: (v) => (v?.isEmpty ?? true) ? 'bank_name_required'.tr : null,
            ),
            const SizedBox(height: 14),
            MyTextField(
              controller: _nameCtrl,
              label: 'account_holder_name'.tr,
              validator: (v) =>
              (v?.isEmpty ?? true) ? 'account_name_required'.tr : null,
            ),
            const SizedBox(height: 14),
            MyTextField(
              controller: _ibanCtrl,
              label: 'iban_label'.tr,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'iban_required'.tr;
                if (v.trim().length < 15) return 'iban_too_short_full'.tr;
                return null;
              },
            ),
            const SizedBox(height: 14),
            MyTextField(
              controller: _swiftCtrl,
              label: 'swift_code_optional'.tr,
            ),
            const SizedBox(height: 16),
            // Set as default toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('set_as_default'.tr,
                        style: c.label.copyWith(fontSize: 13)),
                  ),
                  Switch.adaptive(
                    value: _setAsDefault,
                    onChanged: (v) {
                      if (mounted) setState(() => _setAsDefault = v);
                    },
                    activeColor: c.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            MyPrimaryButton(
              label: 'save_bank_account_btn'.tr,
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

SnackBar _snack(String msg, Color color) => SnackBar(
  content: Text(msg,
      style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
  backgroundColor: color,
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);