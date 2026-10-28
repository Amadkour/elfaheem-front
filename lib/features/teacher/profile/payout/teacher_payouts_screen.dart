// lib/features/teacher/payout/teacher_payouts_screen.dart — balance · payout accounts · withdrawals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_education_app/features/admin/receipt_viewer.dart';
import 'package:provider/provider.dart';

import '../../../../design/app_switch.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/primary_button.dart';
import 'teacher_payout_provider.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/core/display/app_fonts.dart';

class TeacherPayoutsScreen extends StatelessWidget {
  const TeacherPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TeacherPayoutProvider()..load(),
    child: const _View(),
  );
}

Color _statusColor(BuildContext context, String s) {
  final c = context.colors;
  switch (s) {
    case 'paid':
      return c.success;
    case 'approved':
      return c.primary;
    case 'rejected':
      return c.danger;
    default:
      return c.warning;
  }
}

String statusLabel(String s) {
  switch (s) {
    case 'pending':
      return 'doc_pending'.tr;
    case 'approved':
      return 'doc_approved'.tr;
    case 'paid':
      return 'admin_paid_2'.tr;
    case 'rejected':
      return 'withdrawal_status_rejected'.tr;
  }
  return s;
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherPayoutProvider>();
    final c = context.colors;

    Widget body;
    if (!p.loaded) {
      body = const AppListSkeleton(withAvatar: false);
    } else if (p.error != null && p.summary.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else {
      final canRequest =
          p.allowed &&
          p.accounts.isNotEmpty &&
          !p.hasOpenRequest &&
          p.available >= p.minAmount;
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
          children: [
            if (!p.allowed)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock_rounded, color: c.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'admin_withdrawals_are_not_enabled_for_your'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: c.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _BalanceCard(key: const ValueKey('teacher_payouts.balance'), p: p),
            const SizedBox(height: 12),
            PrimaryButton(
              key: const ValueKey('teacher_payouts.request'),
              label: 'admin_request_withdrawal'.tr,
              icon: Icons.account_balance_wallet_rounded,
              onPressed: canRequest ? () => _requestSheet(context, p) : null,
              isLoading: false,
            ),
            if (p.allowed && p.available < p.minAmount)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${'admin_minimum_withdrawal'.tr}: ${money(p.minAmount)}',
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
              ),
            if (p.hasOpenRequest)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'admin_you_have_a_withdrawal_in_progress'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Section(
              title: 'admin_payout_accounts'.tr,
              trailing: TextButton.icon(
                onPressed: p.allowed ? () => _accountSheet(context, p) : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('add'.tr),
              ),
              child: p.accounts.isEmpty
                  ? Text(
                      p.allowed
                          ? 'admin_add_an_account_to_withdraw_bank'.tr
                          : 'admin_no_accounts'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: c.textLight,
                      ),
                    )
                  : Column(
                      children: [for (final a in p.accounts) _AccountTile(a)],
                    ),
            ),
            Section(
              title: 'admin_withdrawals'.tr,
              child: p.withdrawals.isEmpty
                  ? Text(
                      'admin_no_withdrawals_yet'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: c.textLight,
                      ),
                    )
                  : Column(
                      children: [
                        for (final w in p.withdrawals) _WithdrawalTile(w),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: dir,
      child: BasePage(
        key: const ValueKey('teacher_payouts'),
        appBar: AppBar(
          title: Text(
            'admin_earnings_payouts'.tr,
            style: TextStyle(fontFamily: AppFonts.family),
          ),
        ),
        child: body,
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({super.key, required this.p});

  final TeacherPayoutProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, double v) => Expanded(
      child: Column(
        children: [
          Text(
            money(v),
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontWeight: FontWeight.w800,
              color: c.onHero,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: c.onHeroMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'admin_available_to_withdraw'.tr,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: c.onHeroMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            money(p.available),
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontWeight: FontWeight.w900,
              color: c.onHero,
              fontSize: 30,
            ),
          ),
          Divider(color: c.heroGlassBorder, height: 24),
          Row(
            children: [
              cell('admin_total_net'.tr, p.totalNet),
              cell('withdrawn_label'.tr, p.withdrawn),
              cell('admin_in_progress_2'.tr, p.inFlight),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _methodIcon(String m) {
  switch (m) {
    case 'instapay':
      return Icons.bolt_rounded;
    case 'moyasar':
    case 'paymob':
      return Icons.credit_card_rounded;
    default:
      return Icons.account_balance_rounded;
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.a);

  final PayoutAccount a;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<TeacherPayoutProvider>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: c.primary.withValues(alpha: 0.12),
        child: Icon(_methodIcon(a.method), color: c.primary),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              a.label ?? payoutMethodLabel(a.method),
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontWeight: FontWeight.w800,
                color: c.textDark,
              ),
            ),
          ),
          if (a.isDefault) ...[
            const SizedBox(width: 6),
            Icon(Icons.star_rounded, size: 16, color: c.warning),
          ],
        ],
      ),
      subtitle: Text(
        '${payoutMethodLabel(a.method)}${a.currency != null ? ' • ${a.currency}' : ''}\n${a.summary}',
        style: TextStyle(
          fontFamily: AppFonts.family,
          fontSize: 12,
          color: c.textLight,
        ),
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'default') await p.makeDefault(a.id);
          if (v == 'edit') await _accountSheet(context, p, existing: a);
          if (v == 'delete') {
            final ok = await confirm(
              context,
              message: 'admin_remove_this_account'.tr,
              danger: true,
            );
            if (ok) await p.deleteAccount(a.id);
          }
        },
        itemBuilder: (_) => [
          if (!a.isDefault)
            PopupMenuItem(
              value: 'default',
              child: Text('admin_make_default_2'.tr),
            ),
          PopupMenuItem(value: 'edit', child: Text('btn_edit'.tr)),
          PopupMenuItem(value: 'delete', child: Text('course_reel_remove'.tr)),
        ],
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile(this.w);

  final Withdrawal w;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<TeacherPayoutProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                money(w.amount),
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: c.textDark,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                statusLabel(w.status),
                _statusColor(context, w.status),
              ),
              const Spacer(),
              Text(
                shortDate(w.requestedAt),
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 11.5,
                  color: c.textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${payoutMethodLabel(w.method)} • ${payoutDestinationSummary(w.destination)}',
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 12,
              color: c.textMedium,
            ),
          ),
          if (w.status == 'approved' && w.automatic && w.state == 'processing')
            Text(
              'admin_transfer_in_progress_at_the_payment'.tr,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                color: c.primary,
              ),
            ),
          if (w.status == 'approved' && !w.automatic)
            Text(
              'admin_waiting_for_the_admin_to_transfer_it'.tr,
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                color: c.textLight,
              ),
            ),
          if (w.bankReference != null)
            Text(
              '${'admin_reference_2'.tr}: ${w.bankReference}',
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                color: c.success,
              ),
            ),
          if (w.receiptUrl != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: Text(
                  'admin_view_receipt'.tr,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5),
                ),
                onPressed: () async {
                  final p = context.read<TeacherPayoutProvider>();
                  final link = await p.receiptLink(w.id);
                  if (!context.mounted) return;
                  await openReceipt(context, link);
                },
              ),
            ),
          if (w.rejectedReason != null)
            Text(
              '${'admin_reason'.tr}: ${w.rejectedReason}',
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 12,
                color: c.danger,
              ),
            ),
          if (w.status == 'pending')
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    message: 'admin_cancel_this_request'.tr,
                    danger: true,
                  );
                  if (ok) await p.cancelWithdrawal(w.id);
                },
                child: Text(
                  'admin_cancel_request'.tr,
                  style: TextStyle(color: c.danger),
                ),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Request withdrawal
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _requestSheet(BuildContext context, TeacherPayoutProvider p) {
  final amount = TextEditingController();
  final note = TextEditingController();
  int? accountId = p.accounts
      .firstWhere((a) => a.isDefault, orElse: () => p.accounts.first)
      .id;
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return _DisposeWith(
      onDispose: () {
        amount.dispose();
        note.dispose();
      },
      child: StatefulBuilder(
        builder: (ctx, setS) {
          final acct = p.accounts.firstWhere(
            (a) => a.id == accountId,
            orElse: () => p.accounts.first,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader('admin_request_withdrawal'.tr),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'admin_available'.tr}: ${money(p.available)}  •  ${'admin_minimum'.tr}: ${money(p.minAmount)}',
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Field(
                        controller: amount,
                        label: 'admin_amount'.tr,
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      ChoiceRow<int?>(
                        label: 'admin_to_account'.tr,
                        options: {
                          for (final a in p.accounts)
                            a.id: a.label ?? payoutMethodLabel(a.method),
                        },
                        value: accountId,
                        onChanged: (v) => setS(() => accountId = v),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: ctx.colors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          acct.automatic
                              ? 'admin_after_the_admin_approves_the_amount_is'
                                    .tr
                              : 'admin_after_approval_the_admin_transfers_the'
                                    .tr,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Field(
                        controller: note,
                        label: 'admin_note_optional'.tr,
                        maxLines: 2,
                      ),
                      PrimaryButton(
                        label: 'admin_send_request'.tr,
                        isLoading: busy,
                        onPressed: () async {
                          final v = double.tryParse(amount.text.trim());
                          if (v == null || v <= 0) {
                            toast('invalid_amount_error'.tr, error: true);
                            return;
                          }
                          if (v < p.minAmount || v > p.available) {
                            toast(
                              'admin_amount_is_outside_the_allowed_range'.tr,
                              error: true,
                            );
                            return;
                          }
                          setS(() => busy = true);
                          final ok = await p.requestWithdrawal(
                            v,
                            acct.id,
                            note.text.trim().isEmpty ? null : note.text.trim(),
                          );
                          if (ctx.mounted) {
                            setS(() => busy = false);
                            if (ok) Navigator.pop(ctx);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  Add / edit account
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _accountSheet(
  BuildContext context,
  TeacherPayoutProvider p, {
  PayoutAccount? existing,
}) {
  final methods = p.methods;
  if (existing == null && methods.isEmpty) {
    toast('admin_no_payout_methods_are_enabled_for_you'.tr, error: true);
    return Future.value();
  }
  String method = existing?.method ?? methods.first.id;
  final ctrls = <String, TextEditingController>{};
  TextEditingController c(String k) => ctrls.putIfAbsent(
    k,
    () => TextEditingController(text: asStr(existing?.details[k])),
  );
  final label = TextEditingController(text: existing?.label);
  String paymobKind = asStr(existing?.details['kind'], 'wallet');
  String issuer = asStr(existing?.details['issuer'], 'vodafone');
  bool makeDefault = false;
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return _DisposeWith(
      onDispose: () {
        label.dispose();
        for (final x in ctrls.values) {
          x.dispose();
        }
      },
      child: StatefulBuilder(
        builder: (ctx, setS) {
          List<Widget> fields() {
            switch (method) {
              case 'instapay':
                return [
                  Field(
                    controller: c('account_name'),
                    label: 'admin_account_holder'.tr,
                  ),
                  Field(
                    controller: c('instapay_id'),
                    label: 'admin_instapay_address_phone'.tr,
                    ltr: true,
                  ),
                ];
              case 'moyasar':
                return [
                  Field(
                    controller: c('account_name'),
                    label: 'admin_account_holder'.tr,
                  ),
                  Field(
                    controller: c('iban'),
                    label: 'admin_saudi_iban_sa'.tr,
                    ltr: true,
                  ),
                  Field(
                    controller: c('mobile'),
                    label: 'admin_mobile_optional'.tr,
                    keyboard: TextInputType.phone,
                    ltr: true,
                  ),
                  Field(controller: c('city'), label: 'admin_city_optional'.tr),
                ];
              case 'paymob':
                return [
                  ChoiceRow<String>(
                    label: 'admin_type'.tr,
                    options: {
                      'wallet': 'admin_mobile_wallet'.tr,
                      'bank': 'admin_bank_account'.tr,
                    },
                    value: paymobKind,
                    onChanged: (v) => setS(() => paymobKind = v),
                  ),
                  if (paymobKind == 'wallet') ...[
                    ChoiceRow<String>(
                      label: 'admin_wallet'.tr,
                      options: {
                        'vodafone': 'Vodafone Cash',
                        'etisalat': 'Etisalat Cash',
                        'orange': 'Orange Cash',
                        'bank_wallet': 'admin_bank_wallet'.tr,
                      },
                      value: issuer,
                      onChanged: (v) => setS(() => issuer = v),
                    ),
                    Field(
                      controller: c('msisdn'),
                      label: 'admin_wallet_number_01'.tr,
                      keyboard: TextInputType.phone,
                      ltr: true,
                    ),
                  ] else ...[
                    Field(
                      controller: c('bank_code'),
                      label: 'admin_bank_code_e_g_cib'.tr,
                      ltr: true,
                    ),
                    Field(
                      controller: c('bank_card_number'),
                      label: 'admin_account_number_iban'.tr,
                      ltr: true,
                    ),
                  ],
                  Field(
                    controller: c('account_name'),
                    label: 'account_holder_full_name_hint'.tr,
                  ),
                  Field(
                    controller: c('national_id'),
                    label: 'admin_national_id_optional'.tr,
                    keyboard: TextInputType.number,
                    ltr: true,
                  ),
                ];
              default:
                return [
                  Field(
                    controller: c('bank_name'),
                    label: 'admin_bank_name'.tr,
                  ),
                  Field(
                    controller: c('account_name'),
                    label: 'admin_account_holder'.tr,
                  ),
                  Field(controller: c('iban'), label: 'IBAN', ltr: true),
                  Field(
                    controller: c('swift_code'),
                    label: 'admin_swift_optional'.tr,
                    ltr: true,
                  ),
                ];
            }
          }

          List<String> required() {
            switch (method) {
              case 'instapay':
                return ['account_name', 'instapay_id'];
              case 'moyasar':
                return ['account_name', 'iban'];
              case 'paymob':
                return paymobKind == 'wallet'
                    ? ['account_name', 'msisdn']
                    : ['account_name', 'bank_code', 'bank_card_number'];
              default:
                return ['bank_name', 'account_name', 'iban'];
            }
          }

          final info = methods.where((m) => m.id == method).firstOrNull;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(
                existing == null
                    ? 'admin_add_payout_account'.tr
                    : 'admin_edit_account'.tr,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (existing == null)
                        ChoiceRow<String>(
                          label: 'admin_payout_method'.tr,
                          options: {for (final m in methods) m.id: m.label},
                          value: method,
                          onChanged: (v) => setS(() => method = v),
                        ),
                      if (info != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            info.automatic
                                ? trp(
                                    'admin_automatic_transfer_in_after_admin',
                                    {'currency': info.currency},
                                  )
                                : 'admin_manual_transfer_by_the_admin_after'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              fontSize: 12.5,
                              color: ctx.colors.textLight,
                            ),
                          ),
                        ),
                      Field(
                        controller: label,
                        label: 'admin_nickname_optional'.tr,
                      ),
                      ...fields(),
                      if (existing == null)
                        AppSwitchTile(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          title: 'admin_make_default'.tr,
                          value: makeDefault,
                          onChanged: (v) => setS(() => makeDefault = v),
                        ),
                      PrimaryButton(
                        label: 'save'.tr,
                        isLoading: busy,
                        onPressed: () async {
                          for (final k in required()) {
                            if ((ctrls[k]?.text.trim() ?? '').isEmpty) {
                              toast(
                                'admin_fill_in_the_required_fields'.tr,
                                error: true,
                              );
                              return;
                            }
                          }
                          final keys = <String>{
                            ...required(),
                            if (method == 'bank_account') 'swift_code',
                            if (method == 'moyasar') ...['mobile', 'city'],
                            if (method == 'paymob') 'national_id',
                          };
                          final details = <String, dynamic>{
                            for (final k in keys)
                              if ((ctrls[k]?.text.trim() ?? '').isNotEmpty)
                                k: ctrls[k]!.text.trim(),
                            if (method == 'paymob') 'kind': paymobKind,
                            if (method == 'paymob' && paymobKind == 'wallet')
                              'issuer': issuer,
                          };
                          setS(() => busy = true);
                          final ok = await p.saveAccount(
                            id: existing?.id,
                            method: method,
                            label: label.text.trim().isEmpty
                                ? null
                                : label.text.trim(),
                            details: details,
                            makeDefault: makeDefault,
                          );
                          if (ctx.mounted) {
                            setS(() => busy = false);
                            if (ok) Navigator.pop(ctx);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  });
}

/// Runs [onDispose] when the sheet's widget is really removed from the tree —
/// i.e. AFTER the closing animation. Disposing controllers in
/// `showModalBottomSheet(...).whenComplete` is too early: the sheet is still
/// drawing its TextFields while it slides away ("controller used after dispose").
class _DisposeWith extends StatefulWidget {
  const _DisposeWith({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<_DisposeWith> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
