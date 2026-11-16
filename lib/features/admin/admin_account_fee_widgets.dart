// lib/features/admin/admin_account_fee_widgets.dart
//
// The account fee (D-1120) in the admin screens:
//   • AccountFeeRoleRow — one role's switch + amount + currency on the super admin's Platform settings page
//   • AccountFeeChoice — "paid / waived / pays at first sign-in" when an admin creates a teacher or parent
//   • accountFeeStatus — the status of an existing account (for the users list)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'admin_common.dart' show t;
import 'cfg_common.dart' show cfgParseNumber;

/// The roles an account fee can apply to (the server's ACCOUNT_FEE_ROLES).
const accountFeeRoles = ['teacher', 'parent'];

String accountFeeRoleTitle(String role) => role == 'parent'
    ? t('أولياء الأمور يدفعون لفتح الحساب', 'Parents pay to open an account')
    : t('المعلمون يدفعون لفتح الحساب', 'Teachers pay to open an account');

/// The editable state of one role's fee.
class AccountFeeDraft {
  bool on = false;
  final amount = TextEditingController();
  String currency = 'EGP';

  double? get value => amount.text.trim().isEmpty ? null : cfgParseNumber(amount.text);

  void take(Map<String, dynamic> m) {
    on = m['required'] == true;
    final a = (m['amount'] as num?) ?? 0;
    amount.text = a == 0 ? '' : (a == a.roundToDouble() ? '${a.toInt()}' : a.toStringAsFixed(2));
    currency = '${m['currency'] ?? 'EGP'}';
  }

  Map<String, dynamic> get body => {'required': on, 'amount': value ?? 0, 'currency': currency};

  bool differs(Map<String, dynamic> saved) =>
      on != (saved['required'] == true) ||
      (value ?? 0) != ((saved['amount'] as num?) ?? 0).toDouble() ||
      currency != '${saved['currency'] ?? 'EGP'}';
}

/// One role: the switch, then (while on) the amount and the currency.
class AccountFeeRoleRow extends StatelessWidget {
  final String role;
  final AccountFeeDraft draft;
  final List<String> currencies;
  final bool enabled;
  final VoidCallback onChanged;

  const AccountFeeRoleRow({
    super.key,
    required this.role,
    required this.draft,
    required this.currencies,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = draft.value;
    final subtitle = draft.on
        ? (v != null && v > 0
            ? t('${_fmt(v)} ${draft.currency} مرة واحدة عند فتح الحساب', '${_fmt(v)} ${draft.currency}, once, to open the account')
            : t('اكتب المبلغ', 'Enter the amount'))
        : t('مجاني', 'Free');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppSwitchTile(
        key: ValueKey('account_fee.$role'),
        icon: role == 'parent' ? Icons.family_restroom_rounded : Icons.school_rounded,
        title: accountFeeRoleTitle(role),
        subtitle: subtitle,
        value: draft.on,
        onChanged: enabled
            ? (on) {
                draft.on = on;
                onChanged();
              }
            : null,
      ),
      AnimatedSize(
        duration: AppMotion.of(context).base,
        child: !draft.on
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
                child: LayoutBuilder(builder: (context, box) {
                  final amount = AbsorbPointer(
                    absorbing: !enabled,
                    child: AppField(
                      key: ValueKey('account_fee.$role.amount'),
                      controller: draft.amount,
                      label: t('المبلغ', 'Amount'),
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      ltr: true,
                      onChanged: (_) => onChanged(),
                    ),
                  );
                  final currency = AbsorbPointer(
                    absorbing: !enabled,
                    child: AppPicker<String>(
                      label: t('العملة', 'Currency'),
                      icon: Icons.currency_exchange_rounded,
                      value: draft.currency,
                      options: {for (final x in currencies) x: x},
                      onChanged: (x) {
                        draft.currency = x ?? draft.currency;
                        onChanged();
                      },
                    ),
                  );
                  if (box.maxWidth < 460) return Column(children: [amount, currency]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: amount),
                    AppSpace.gapSm,
                    Expanded(flex: 2, child: currency),
                  ]);
                }),
              ),
      ),
    ]);
  }

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
}

/// What an admin creating a teacher / parent decides about the fee: `paid` (default), `waived`, `pay_later`.
class AccountFeeChoice extends StatelessWidget {
  final String value;
  final String feeLabel;
  final ValueChanged<String> onChanged;

  const AccountFeeChoice({super.key, required this.value, required this.feeLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = {
      'paid': t('مدفوعة', 'Paid'),
      'waived': t('إعفاء', 'Waived'),
      'pay_later': t('يدفع عند أول دخول', 'Pays at first sign-in'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('رسوم فتح الحساب · $feeLabel', 'Account fee · $feeLabel'), style: AppType.label(context)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final o in options.entries)
          AppChoiceChip(
            key: ValueKey('account_fee_choice.${o.key}'),
            label: o.value,
            selected: value == o.key,
            onTap: () => onChanged(o.key),
          ),
      ]),
    ]);
  }
}

/// `paid` · `waived` · `due` (owes it now) · null (never asked). [feeOn]: the role's fee is on right now.
String? accountFeeStatus(Map<String, dynamic> user, {required bool feeOn}) {
  if (user['account_fee_paid_at'] != null) return 'paid';
  if (user['account_fee_waived'] == true) return 'waived';
  if (user['account_fee_required'] == true && feeOn) return 'due';
  return null;
}

String accountFeeStatusLabel(String status) => switch (status) {
      'paid' => t('رسوم الحساب مدفوعة', 'Account fee paid'),
      'waived' => t('معفى من رسوم الحساب', 'Account fee waived'),
      _ => t('لم يدفع رسوم الحساب', 'Account fee not paid'),
    };
