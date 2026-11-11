// lib/features/teacher/payout/teacher_payouts_screen.dart — balance · payout accounts · withdrawals.
library;

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_education_app/features/admin/receipt_viewer.dart';
import 'package:provider/provider.dart';

import '../../../../design/app_switch.dart';
import '../../../../utils/widget/base_page.dart';
import 'teacher_payout_provider.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBlock, AppBlockTone, AppBorder, AppButton, AppButtonSize, AppButtonVariant, AppCard, AppErrorState, AppIconSize,
        AppListSkeleton, AppNumberField, AppRadius, AppSection, AppSettingsTile, AppSpace, AppStatusBadge, AppTone, AppType,
        AppWidth, AppWidthBox, appInkOn, appTintOn;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppOdometer, AppReveal, AppTilt;

class TeacherPayoutsScreen extends StatelessWidget {
  const TeacherPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => TeacherPayoutProvider()..load(),
    child: const _View(),
  );
}

AppTone _statusTone(String s) {
  switch (s) {
    case 'paid':
      return AppTone.success;
    case 'approved':
      return AppTone.info;
    case 'rejected':
      return AppTone.danger;
    default:
      return AppTone.warning;
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

    Widget body;
    if (!p.loaded) {
      body = const AppListSkeleton(withAvatar: false);
    } else if (p.error != null && p.summary.isEmpty) {
      body = AppErrorState(message: p.error!, onRetry: p.load);
    } else {
      final canRequest =
          p.allowed &&
          p.accounts.isNotEmpty &&
          !p.hasOpenRequest &&
          p.available >= p.minAmount;
      final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
      final note = <String>[
        if (p.allowed && p.available < p.minAmount) '${'admin_minimum_withdrawal'.tr}: ${money(p.minAmount)}',
        if (p.hasOpenRequest) 'admin_you_have_a_withdrawal_in_progress'.tr,
      ];
      // ONE entrance (system.md §6): the balance block leads, the request button and the two sections follow once
      Widget enter(int i, Widget w) => AppReveal(index: i, group: 'teacher_payouts', child: w);
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xxl),
          children: [
            AppWidthBox(
              width: AppWidth.reading,
              gutters: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!p.allowed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: _Notice(icon: Icons.lock_clock_rounded, text: 'admin_withdrawals_are_not_enabled_for_your'.tr),
                  ),
                enter(0, _BalanceCard(key: const ValueKey('teacher_payouts.balance'), p: p)),
                const SizedBox(height: AppSpace.md),
                enter(
                  1,
                  AppButton.primary(
                    key: const ValueKey('teacher_payouts.request'),
                    expand: true,
                    size: AppButtonSize.lg,
                    label: 'admin_request_withdrawal'.tr,
                    icon: Icons.account_balance_wallet_rounded,
                    onPressed: canRequest ? () => _requestSheet(context, p) : null,
                  ),
                ),
                for (final line in note)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(line, style: AppType.meta(context)),
                  ),
                enter(
                  2,
                  AppSection(
                    title: 'admin_payout_accounts'.tr,
                    trailing: AppButton.ghost(
                      size: AppButtonSize.sm,
                      label: 'add'.tr,
                      icon: Icons.add_rounded,
                      onPressed: p.allowed ? () => _accountSheet(context, p) : null,
                    ),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                      child: p.accounts.isEmpty
                          ? Padding(
                              padding: AppSpace.card,
                              child: Text(
                                p.allowed ? 'admin_add_an_account_to_withdraw_bank'.tr : 'admin_no_accounts'.tr,
                                style: AppType.body(context),
                              ),
                            )
                          : _Rows(children: [for (final a in p.accounts) _AccountTile(a)]),
                    ),
                  ),
                ),
                enter(
                  3,
                  AppSection(
                    title: 'admin_withdrawals'.tr,
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                      child: p.withdrawals.isEmpty
                          ? Padding(
                              padding: AppSpace.card,
                              child: Text('admin_no_withdrawals_yet'.tr, style: AppType.body(context)),
                            )
                          : _Rows(children: [for (final w in p.withdrawals) _WithdrawalTile(w)]),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: dir,
      child: BasePage(
        key: const ValueKey('teacher_payouts'),
        appBar: ScreenAppBar(title: 'admin_earnings_payouts'.tr), // the app's back chip + title (L4)
        child: body,
      ),
    );
  }
}

/// Rows of a paper card parted by warm hairlines that start where the text starts.
class _Rows extends StatelessWidget {
  const _Rows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          Divider(
            height: AppBorder.hairline,
            thickness: AppBorder.hairline,
            color: c.divider,
            indent: AppSpace.md,
            endIndent: AppSpace.md,
          ),
        children[i],
      ],
    ]);
  }
}

/// A calm notice on the canvas: the warning tint, its glyph in a legible warning ink, the text in ink.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, c.warning);
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(children: [
        Icon(icon, size: AppIconSize.md, color: appInkOn(context, c.warning, tint)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textDark))),
      ]),
    );
  }
}

/// The page's ONE block (the KPI highlight language, D-612): what can be withdrawn now as the rolling key figure,
/// the three running totals under a quiet rule, counting up once. It leans under the pointer (the key KPI).
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({super.key, required this.p});

  final TeacherPayoutProvider p;

  /// How much of the block's ink the rules between the totals carry.
  static const double _ruleInk = 0.16;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AppTilt(
          radius: AppRadius.block,
          maxTilt: 2.5,
          glare: true,
          child: AppBlock(
            tone: AppBlockTone.peach,
            hero: true,
            child: Builder(builder: (context) {
              final b = AppBlock.colorsOf(context);
              final rule = Color.lerp(b.surface, b.ink, _ruleInk)!;
              Widget cell(String label, double v, String key) => Expanded(
                    child: Column(children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AppCountUp(money(v), memoryKey: 'payouts.$key', style: AppType.figure(context).copyWith(color: b.ink)),
                      ),
                      const SizedBox(height: AppSpace.xxs),
                      Text(label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.meta(context).copyWith(color: b.muted)),
                    ]),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('admin_available_to_withdraw'.tr, style: AppType.label(context).copyWith(color: b.muted)),
                const SizedBox(height: AppSpace.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AppOdometer(
                      money(p.available),
                      memoryKey: 'payouts.available',
                      style: AppType.figureLarge(context).copyWith(color: b.ink),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: rule),
                const SizedBox(height: AppSpace.md),
                IntrinsicHeight(
                  child: Row(children: [
                    cell('admin_total_net'.tr, p.totalNet, 'net'),
                    VerticalDivider(width: AppSpace.lg, thickness: AppBorder.hairline, color: rule),
                    cell('withdrawn_label'.tr, p.withdrawn, 'withdrawn'),
                    VerticalDivider(width: AppSpace.lg, thickness: AppBorder.hairline, color: rule),
                    cell('admin_in_progress_2'.tr, p.inFlight, 'in_flight'),
                  ]),
                ),
              ]);
            }),
          ),
        ),
      );
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
    final well = appTintOn(context, c.primary, surface: c.cardBg);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: AppSettingsTile.well,
          height: AppSettingsTile.well,
          decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
          child: Icon(_methodIcon(a.method), size: AppIconSize.md, color: appInkOn(context, c.primary, well)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(a.label ?? payoutMethodLabel(a.method),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              ),
              if (a.isDefault) ...[
                const SizedBox(width: AppSpace.xxs),
                Icon(Icons.star_rounded, size: AppIconSize.sm, color: c.primary),
              ],
            ]),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(
              '${payoutMethodLabel(a.method)}${a.currency != null ? ' • ${a.currency}' : ''}\n${a.summary}',
              style: AppType.meta(context),
            ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'btn_edit'.tr,
          icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
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
      ]),
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
    final line = AppType.meta(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(money(w.amount), style: AppType.figure(context)),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppStatusBadge(label: statusLabel(w.status), tone: _statusTone(w.status)),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Text(shortDate(w.requestedAt), style: line),
            ],
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            '${payoutMethodLabel(w.method)} • ${payoutDestinationSummary(w.destination)}',
            style: line,
          ),
          if (w.status == 'approved' && w.automatic && w.state == 'processing')
            Text('admin_transfer_in_progress_at_the_payment'.tr, style: line.copyWith(color: c.textDark)),
          if (w.status == 'approved' && !w.automatic)
            Text('admin_waiting_for_the_admin_to_transfer_it'.tr, style: line),
          if (w.bankReference != null)
            Text('${'admin_reference_2'.tr}: ${w.bankReference}', style: line.copyWith(color: c.textDark)),
          if (w.receiptUrl != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                size: AppButtonSize.sm,
                icon: Icons.receipt_long_rounded,
                label: 'admin_view_receipt'.tr,
                onPressed: () async {
                  final p = context.read<TeacherPayoutProvider>();
                  final link = await p.receiptLink(w.id);
                  if (!context.mounted) return;
                  await openReceipt(context, link);
                },
              ),
            ),
          if (w.rejectedReason != null)
            Text('${'admin_reason'.tr}: ${w.rejectedReason}',
                style: line.copyWith(color: c.blockAccentInk(c.danger, c.cardBg))),
          if (w.status == 'pending')
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton(
                variant: AppButtonVariant.danger,
                dangerOutline: true,
                size: AppButtonSize.sm,
                label: 'admin_cancel_request'.tr,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    message: 'admin_cancel_this_request'.tr,
                    danger: true,
                  );
                  if (ok) await p.cancelWithdrawal(w.id);
                },
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'admin_available'.tr}: ${money(p.available)}  •  ${'admin_minimum'.tr}: ${money(p.minAmount)}',
                        style: AppType.label(ctx),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      AppNumberField(
                        controller: amount,
                        label: 'admin_amount'.tr,
                        min: 0,
                        step: 50,
                        decimals: 2,
                      ),
                      const SizedBox(height: AppSpace.sm),
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
                        padding: const EdgeInsets.all(AppSpace.sm),
                        margin: const EdgeInsets.only(bottom: AppSpace.sm),
                        decoration: BoxDecoration(
                          color: appTintOn(ctx, ctx.colors.primary),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Text(
                          acct.automatic
                              ? 'admin_after_the_admin_approves_the_amount_is'
                                    .tr
                              : 'admin_after_approval_the_admin_transfers_the'
                                    .tr,
                          style: AppType.label(ctx).copyWith(color: ctx.colors.textDark),
                        ),
                      ),
                      Field(
                        controller: note,
                        label: 'admin_note_optional'.tr,
                        maxLines: 2,
                      ),
                      AppButton.primary(
                        expand: true,
                        label: 'admin_send_request'.tr,
                        busy: busy,
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
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
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
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: Text(
                            info.automatic
                                ? trp(
                                    'admin_automatic_transfer_in_after_admin',
                                    {'currency': info.currency},
                                  )
                                : 'admin_manual_transfer_by_the_admin_after'.tr,
                            style: AppType.meta(ctx),
                          ),
                        ),
                      Field(
                        controller: label,
                        label: 'admin_nickname_optional'.tr,
                      ),
                      ...fields(),
                      if (existing == null)
                        AppSwitchTile(
                          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                          title: 'admin_make_default'.tr,
                          value: makeDefault,
                          onChanged: (v) => setS(() => makeDefault = v),
                        ),
                      AppButton.primary(
                        expand: true,
                        label: 'save'.tr,
                        busy: busy,
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
/// `showAppModalSheet(...).whenComplete` is too early: the sheet is still
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
