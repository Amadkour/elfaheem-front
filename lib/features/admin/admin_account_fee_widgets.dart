// lib/features/admin/admin_account_fee_widgets.dart
//
// The account fee (D-1120) and the registration modes (D-1121) in the admin screens:
//   • AccountFeeRoleRow — one role's mode (free / paid / approval / paid + approval) + amount + currency on the
//     super admin's Platform settings page
//   • AccountFeeChoice — "paid / waived / pays at first sign-in" when an admin creates a teacher or parent
//   • accountFeeStatus — the status of an existing account (for the users list)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'admin_common.dart' show t;
import 'cfg_common.dart' show cfgParseNumber;

/// The roles a registration mode applies to (the server's ACCOUNT_FEE_ROLES; students since D-1121).
const accountFeeRoles = ['teacher', 'parent', 'student'];

/// The four registration modes (D-1121), in the order the super admin sees them.
const registrationModes = ['free', 'paid', 'approval', 'paid_approval'];

bool modeCharges(String mode) => mode == 'paid' || mode == 'paid_approval';

bool modeNeedsApproval(String mode) => mode == 'approval' || mode == 'paid_approval';

String accountFeeRoleTitle(String role) => switch (role) {
      'parent' => t('أولياء الأمور', 'Parents'),
      'student' => t('الطلاب', 'Students'),
      _ => t('المعلمون', 'Teachers'),
    };

String registrationModeLabel(String mode) => switch (mode) {
      'paid' => t('دفع رسوم', 'Pay a fee'),
      'approval' => t('موافقة الإدارة', 'Admin approval'),
      'paid_approval' => t('دفع + موافقة', 'Pay + approval'),
      _ => t('مجاني بدون موافقة', 'Free, no approval'),
    };

String registrationModeHint(String mode) => switch (mode) {
      'paid' => t('يدفع الحساب الجديد الرسوم مرة واحدة ثم يبدأ مباشرة.', 'A new account pays the fee once, then starts right away.'),
      'approval' => t('ينتظر الحساب الجديد موافقة مدير المنصة قبل أن يبدأ.', 'A new account waits for a platform admin to approve it.'),
      'paid_approval' => t('يدفع الحساب الجديد الرسوم أولاً، ثم ينتظر موافقة الإدارة.', 'A new account pays the fee first, then waits for an admin to approve it.'),
      _ => t('يبدأ الحساب الجديد فور تأكيد بياناته.', 'A new account starts as soon as its details are confirmed.'),
    };

/// The editable state of one role: its registration mode and, for the paid modes, the fee.
class AccountFeeDraft {
  String mode = 'free';
  final amount = TextEditingController();
  String currency = 'EGP';

  /// The mode charges the fee.
  bool get on => modeCharges(mode);

  double? get value => amount.text.trim().isEmpty ? null : cfgParseNumber(amount.text);

  static String modeOf(Map<String, dynamic> m) {
    final x = '${m['mode'] ?? ''}';
    if (registrationModes.contains(x)) return x;
    return m['required'] == true ? 'paid' : 'free'; // a D-1120 server
  }

  void take(Map<String, dynamic> m) {
    mode = modeOf(m);
    final a = (m['amount'] as num?) ?? 0;
    amount.text = a == 0 ? '' : (a == a.roundToDouble() ? '${a.toInt()}' : a.toStringAsFixed(2));
    currency = '${m['currency'] ?? 'EGP'}';
  }

  Map<String, dynamic> get body => {'mode': mode, 'required': on, 'amount': value ?? 0, 'currency': currency};

  bool differs(Map<String, dynamic> saved) =>
      mode != modeOf(saved) ||
      (value ?? 0) != ((saved['amount'] as num?) ?? 0).toDouble() ||
      currency != '${saved['currency'] ?? 'EGP'}';
}

/// One role: the four modes, a one-line explanation of the chosen one, then (paid modes) the amount and currency.
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
    final c = context.colors;
    final v = draft.value;
    final price = draft.on && v != null && v > 0 ? ' · ${_fmt(v)} ${draft.currency}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              switch (role) {
                'parent' => Icons.family_restroom_rounded,
                'student' => Icons.backpack_rounded,
                _ => Icons.school_rounded,
              },
              size: AppIconSize.md,
              color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text('${accountFeeRoleTitle(role)}$price',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in registrationModes)
            AppChoiceChip(
              key: ValueKey('account_fee.$role.$m'),
              label: registrationModeLabel(m),
              icon: switch (m) {
                'paid' => Icons.payments_rounded,
                'approval' => Icons.how_to_reg_rounded,
                'paid_approval' => Icons.verified_user_rounded,
                _ => Icons.lock_open_rounded,
              },
              selected: draft.mode == m,
              onTap: () {
                if (!enabled || draft.mode == m) return;
                draft.mode = m;
                onChanged();
              },
            ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(registrationModeHint(draft.mode),
            key: ValueKey('account_fee.$role.hint'), style: AppType.meta(context)),
        AnimatedSize(
          duration: AppMotion.of(context).base,
          child: !draft.on
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpace.sm),
                  child: LayoutBuilder(builder: (context, box) {
                    final amount = AbsorbPointer(
                      absorbing: !enabled,
                      child: AppField(
                        key: ValueKey('account_fee.$role.amount'),
                        controller: draft.amount,
                        label: t('الرسوم (مرة واحدة)', 'Fee (once)'),
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
      ]),
    );
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
