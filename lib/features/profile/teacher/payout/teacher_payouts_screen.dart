// lib/features/profile/teacher/payout/teacher_payouts_screen.dart — balance · payout accounts · withdrawals.
//
// The redesign (Tea2Money.dc.html?screen=earn / withdraw / addacc): the teacher's hero band carries what can be
// withdrawn now as the page's figure, the one forward button ("Request a withdrawal") and the three running totals;
// the body rides up over it: a notice while a request is open, the history, the payout accounts and how the money
// reaches the teacher. The request and the account forms are sheets (M14). The fields a bank account asks for come
// from the server per residence country (any IBAN country, or an account number + SWIFT where there is no IBAN).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart'
    show asStr, confirm, dir, money, shortDate, toast, trp;
import 'package:flutter_education_app/features/admin/admin_models.dart';
import 'package:flutter_education_app/features/admin/receipt_viewer.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payout_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:provider/provider.dart';

class TeacherPayoutsScreen extends StatelessWidget {
  const TeacherPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => TeacherPayoutProvider()..load(),
        child: const TeacherPayoutsView(),
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

/// The page over a [TeacherPayoutProvider] above it (the screen creates one; a test passes its own).
class TeacherPayoutsView extends StatelessWidget {
  const TeacherPayoutsView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherPayoutProvider>();
    final title = 'admin_earnings_payouts'.tr;

    final Widget hero;
    final List<Widget> body;
    if (!p.loaded) {
      hero = AppHero(kicker: 'admin_available_to_withdraw'.tr, title: '…');
      body = [const AppLoadingState(shape: AppLoadingShape.cards, items: 3)];
    } else if (p.error != null && p.summary.isEmpty) {
      hero = AppHero(kicker: 'admin_available_to_withdraw'.tr, title: '—');
      body = [AppCard(child: AppErrorState(message: p.error!, onRetry: p.load))];
    } else {
      final canRequest = p.allowed && p.accounts.isNotEmpty && !p.hasOpenRequest && p.available >= p.minAmount;
      hero = AppHero(
        key: const ValueKey('teacher_payouts.balance'),
        kicker: 'admin_available_to_withdraw'.tr,
        title: money(p.available),
        subtitle: 't2_pay_after_fees'.tr,
        actions: [
          AppButton.hot(
            key: const ValueKey('teacher_payouts.request'),
            label: 't2_pay_request'.tr,
            icon: Icons.payments_outlined,
            onPressed: canRequest ? () => _requestSheet(context, p) : null,
          ),
        ],
        stats: [
          AppHeroStat(value: money(p.totalNet), label: 'admin_total_net'.tr),
          AppHeroStat(value: money(p.withdrawn), label: 'withdrawn_label'.tr),
          AppHeroStat(value: money(p.inFlight), label: 'admin_in_progress_2'.tr),
        ],
      );
      body = [
        if (!p.allowed) _Notice(icon: Icons.lock_clock_rounded, text: 'admin_withdrawals_are_not_enabled_for_your'.tr),
        if (p.hasOpenRequest)
          _Notice(
            icon: Icons.schedule_rounded,
            strong: 't2_pay_open_strong'.tr,
            text: 't2_pay_open_rest'.tr,
          ),
        if (p.allowed && !p.hasOpenRequest && p.available < p.minAmount)
          _Notice(icon: Icons.info_outline_rounded, text: '${'admin_minimum_withdrawal'.tr}: ${money(p.minAmount)}'),
        T2Columns(
          start: [_HistoryCard(p: p)],
          end: [_AccountsCard(p: p), _HowCard(min: p.minAmount)],
        ),
      ];
    }

    return Directionality(
      textDirection: dir,
      child: T2HeroPage(
        pageKey: const ValueKey('teacher_payouts'),
        title: title,
        onRefresh: p.load,
        hero: hero,
        children: body,
      ),
    );
  }
}

/// A calm notice on the page: the warn tint, its glyph in the warn ink, an optional bold lead.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.strong});

  final IconData icon;
  final String text;
  final String? strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = c.kit.warn;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: warn.tint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: Color.lerp(warn.tint, warn.color, .35)!, width: AppBorder.strong),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.md, color: warn.ink),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (strong != null) TextSpan(text: '$strong ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: text),
            ]),
            style: AppType.body(context).copyWith(color: warn.ink),
          ),
        ),
      ]),
    );
  }
}

/// The history of requests (newest first).
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.p});

  final TeacherPayoutProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      title: 'admin_withdrawals'.tr,
      child: p.withdrawals.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Text('admin_no_withdrawals_yet'.tr, style: AppType.body(context)),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < p.withdrawals.length; i++) ...[
                if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.kit.line),
                _WithdrawalTile(p.withdrawals[i]),
              ],
            ]),
    );
  }
}

/// "Payout accounts": each one a bordered tile (the default one highlighted), "+ Add" in the head.
class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.p});

  final TeacherPayoutProvider p;

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'admin_payout_accounts'.tr,
        action: AppButton.ghost(
          key: const ValueKey('teacher_payouts.add_account'),
          size: AppButtonSize.sm,
          label: 't2_pay_add'.tr,
          icon: Icons.add_rounded,
          onPressed: p.allowed ? () => _accountSheet(context, p) : null,
        ),
        child: p.accounts.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Text(
                  p.allowed ? 'admin_add_an_account_to_withdraw_bank'.tr : 'admin_no_accounts'.tr,
                  style: AppType.body(context),
                ),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < p.accounts.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpace.sm),
                  _AccountTile(p.accounts[i]),
                ],
              ]),
      );
}

/// "How does the money reach you?": three numbered steps on the dark card.
class _HowCard extends StatelessWidget {
  const _HowCard({required this.min});

  final double min;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = [
      trp('t2_pay_how_1', {'min': money(min)}),
      't2_pay_how_2'.tr,
      't2_pay_how_3'.tr,
    ];
    return AppCard(
      variant: AppCardVariant.dark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('t2_pay_how_title'.tr, style: AppType.section(context).copyWith(color: c.onHero)),
        const SizedBox(height: AppSpace.sm),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: AppSpace.lg,
                height: AppSpace.lg,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.heroGlass, shape: BoxShape.circle),
                child: Text('${i + 1}', style: AppType.overline(context).copyWith(color: c.onHero)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(steps[i], style: AppType.label(context).copyWith(color: c.onHero))),
            ]),
          ),
      ]),
    );
  }
}

IconData _methodIcon(String m) {
  switch (m) {
    case 'instapay':
      return Icons.bolt_rounded;
    case 'moyasar':
    case 'paymob':
      return Icons.account_balance_wallet_outlined;
    default:
      return Icons.account_balance_rounded;
  }
}

/// One payout account: glyph, name (+ "Default"), the masked destination, and its menu.
class _AccountTile extends StatelessWidget {
  const _AccountTile(this.a);

  final PayoutAccount a;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<TeacherPayoutProvider>();
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
      decoration: BoxDecoration(
        gradient: a.isDefault ? LinearGradient(colors: [c.cardBg, set.tint]) : null,
        color: a.isDefault ? null : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: a.isDefault ? Color.lerp(set.tint, set.a, .45)! : c.kit.line,
          width: AppBorder.strong,
        ),
      ),
      child: Row(children: [
        AppIconBox(icon: _methodIcon(a.method), tone: c.kit.primaryTone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(a.label ?? payoutMethodLabel(a.method), style: AppType.tileTitle(context)),
              if (a.isDefault) AppStatusBadge(label: 't2_pay_default'.tr, tone: AppTone.brand),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(
              a.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: AppConfig.lang == 'ar' ? TextAlign.right : TextAlign.left,
              style: AppType.meta(context),
            ),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'btn_edit'.tr,
          icon: Icon(Icons.more_horiz_rounded, color: c.textMedium),
          onSelected: (v) async {
            if (v == 'default') await p.makeDefault(a.id);
            if (v == 'edit' && context.mounted) await _accountSheet(context, p, existing: a);
            if (v == 'delete' && context.mounted) {
              final ok = await confirm(context, message: 'admin_remove_this_account'.tr, danger: true);
              if (ok) await p.deleteAccount(a.id);
            }
          },
          itemBuilder: (_) => [
            if (!a.isDefault) PopupMenuItem(value: 'default', child: Text('admin_make_default_2'.tr)),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(money(w.amount), style: AppType.figure(context)),
          AppStatusBadge(label: statusLabel(w.status), tone: _statusTone(w.status)),
          Text(shortDate(w.requestedAt), style: line),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text('${payoutMethodLabel(w.method)} • ${payoutDestinationSummary(w.destination)}', style: line),
        if (w.status == 'approved' && w.automatic && w.state == 'processing')
          Text('admin_transfer_in_progress_at_the_payment'.tr, style: line.copyWith(color: c.textDark)),
        if (w.status == 'approved' && !w.automatic) Text('admin_waiting_for_the_admin_to_transfer_it'.tr, style: line),
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
                final link = await p.receiptLink(w.id);
                if (!context.mounted) return;
                await openReceipt(context, link);
              },
            ),
          ),
        if (w.rejectedReason != null)
          Text('${'admin_reason'.tr}: ${w.rejectedReason}', style: line.copyWith(color: c.kit.error.ink)),
        if (w.status == 'pending')
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              variant: AppButtonVariant.danger,
              dangerOutline: true,
              size: AppButtonSize.sm,
              label: 'admin_cancel_request'.tr,
              onPressed: () async {
                final ok = await confirm(context, message: 'admin_cancel_this_request'.tr, danger: true);
                if (ok) await p.cancelWithdrawal(w.id);
              },
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Request withdrawal (Tea2Money.dc.html?screen=withdraw)
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _requestSheet(BuildContext context, TeacherPayoutProvider p) {
  return showAppSheet<void>(context, (ctx) => ChangeNotifierProvider.value(value: p, child: const _RequestForm()));
}

/// The request form: the available amount, the amount with quick picks, the account (one tile each), a note.
class _RequestForm extends StatefulWidget {
  const _RequestForm();

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  int? _accountId;
  bool _busy = false;

  /// The quick amounts offered under the field (those not above the balance).
  static const _quick = [1000.0, 5000.0];

  @override
  void initState() {
    super.initState();
    final p = context.read<TeacherPayoutProvider>();
    _accountId = p.accounts.firstWhere((a) => a.isDefault, orElse: () => p.accounts.first).id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _send(TeacherPayoutProvider p, PayoutAccount acct) async {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v <= 0) {
      toast('invalid_amount_error'.tr, error: true);
      return;
    }
    if (v < p.minAmount || v > p.available) {
      toast('admin_amount_is_outside_the_allowed_range'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await p.requestWithdrawal(v, acct.id, _note.text.trim().isEmpty ? null : _note.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherPayoutProvider>();
    final c = context.colors;
    final ok = c.kit.ok;
    final acct = p.accounts.firstWhere((a) => a.id == _accountId, orElse: () => p.accounts.first);
    final picks = [for (final q in _quick) if (q <= p.available && q >= p.minAmount) q];
    return AppSheetContent(
      title: 't2_pay_request'.tr,
      icon: Icons.payments_outlined,
      tone: AppTone.success,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          decoration: BoxDecoration(color: ok.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Row(children: [
            Expanded(child: Text('admin_available_to_withdraw'.tr, style: AppType.label(context).copyWith(color: ok.ink))),
            Text(money(p.available), style: AppType.figure(context).copyWith(color: ok.ink)),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        AppNumberField(
          controller: _amount,
          label: 'admin_amount'.tr,
          min: 0,
          step: 50,
          decimals: 2,
          helper: trp('t2_pay_range', {'min': money(p.minAmount)}),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final q in picks)
            AppChip(
              label: _plain(q),
              selected: _amount.text == _plain(q),
              onTap: () => setState(() => _amount.text = _plain(q)),
            ),
          AppChip(
            label: 't2_pay_all'.tr,
            selected: _amount.text == _plain(p.available),
            onTap: () => setState(() => _amount.text = _plain(p.available)),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        AppFieldLabel('admin_to_account'.tr),
        for (final a in p.accounts) ...[
          AppTile(
            icon: _methodIcon(a.method),
            title: a.label ?? payoutMethodLabel(a.method),
            subtitle: a.summary,
            selected: a.id == acct.id,
            trailing: Icon(
              a.id == acct.id ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: a.id == acct.id ? AppAreaScope.of(context).a : c.textLight,
            ),
            onTap: () => setState(() => _accountId = a.id),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.xs),
        AppField(controller: _note, label: 'admin_note_optional'.tr, hint: 't2_pay_note_hint'.tr, maxLines: 2),
        const SizedBox(height: AppSpace.sm),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.kit.primaryTone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: c.kit.primaryTone.ink),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                acct.automatic
                    ? 'admin_after_the_admin_approves_the_amount_is'.tr
                    : 'admin_after_approval_the_admin_transfers_the'.tr,
                style: AppType.label(context).copyWith(color: c.kit.primaryTone.ink),
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        AppButtonRow(
          primary: AppButton.primary(
            label: 'admin_send_request'.tr,
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: () => _send(p, acct),
          ),
          secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Add / edit account (Tea2Money.dc.html?screen=addacc)
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _accountSheet(BuildContext context, TeacherPayoutProvider p, {PayoutAccount? existing}) {
  if (existing == null && p.methods.isEmpty) {
    toast('admin_no_payout_methods_are_enabled_for_you'.tr, error: true);
    return Future.value();
  }
  return showAppSheet<void>(
      context, (ctx) => ChangeNotifierProvider.value(value: p, child: _AccountForm(existing: existing)));
}

/// The label of a payout field the server names.
String _fieldLabel(String key) => switch (key) {
      'account_name' => 'admin_account_holder'.tr,
      'bank_name' => 'admin_bank_name'.tr,
      'iban' => 't2_pay_iban'.tr,
      'swift_code' => 't2_pay_swift'.tr,
      'account_number' => 't2_pay_account_number'.tr,
      'mobile' => 'admin_mobile_optional'.tr,
      'city' => 'admin_city_optional'.tr,
      'national_id' => 'admin_national_id_optional'.tr,
      _ => key,
    };

class _AccountForm extends StatefulWidget {
  const _AccountForm({this.existing});

  final PayoutAccount? existing;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late String _method;
  final _ctrls = <String, TextEditingController>{};
  late final _label = TextEditingController(text: widget.existing?.label);
  late String _paymobKind = asStr(widget.existing?.details['kind'], 'wallet');
  late String _issuer = asStr(widget.existing?.details['issuer'], 'vodafone');
  bool _makeDefault = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _method = widget.existing?.method ?? context.read<TeacherPayoutProvider>().methods.first.id;
  }

  @override
  void dispose() {
    _label.dispose();
    for (final x in _ctrls.values) {
      x.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String k) =>
      _ctrls.putIfAbsent(k, () => TextEditingController(text: asStr(widget.existing?.details[k])));

  Widget _field(String key, {String? label, bool ltr = false, TextInputType? keyboard, bool required = false, String? helper}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppField(
          controller: _c(key),
          label: label ?? _fieldLabel(key),
          ltr: ltr,
          keyboard: keyboard,
          required: required,
          helper: helper,
        ),
      );

  /// The server's field list for a bank account in the teacher's country (WP8), when it sent one.
  List<({String key, bool required})> _serverFields(TeacherPayoutProvider p) =>
      p.methods.where((m) => m.id == _method).firstOrNull?.fields ?? const [];

  List<Widget> _fields(TeacherPayoutProvider p) {
    switch (_method) {
      case 'instapay':
        return [
          _field('account_name', required: true, helper: 't2_pay_name_hint'.tr),
          _field('instapay_id', label: 'admin_instapay_address_phone'.tr, ltr: true, required: true),
        ];
      case 'moyasar':
        return [
          _field('account_name', required: true, helper: 't2_pay_name_hint'.tr),
          _field('iban', label: 'admin_saudi_iban_sa'.tr, ltr: true, required: true),
          _field('mobile', keyboard: TextInputType.phone, ltr: true),
          _field('city'),
        ];
      case 'paymob':
        return [
          AppTabs(
            expand: true,
            items: [AppTabItem('admin_mobile_wallet'.tr), AppTabItem('admin_bank_account'.tr)],
            index: _paymobKind == 'wallet' ? 0 : 1,
            onChanged: (i) => setState(() => _paymobKind = i == 0 ? 'wallet' : 'bank'),
          ),
          const SizedBox(height: AppSpace.sm),
          if (_paymobKind == 'wallet') ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppDropdown<String>(
                decoration: InputDecoration(labelText: 'admin_wallet'.tr),
                value: _issuer,
                items: [
                  for (final e in {
                    'vodafone': 'Vodafone Cash',
                    'etisalat': 'Etisalat Cash',
                    'orange': 'Orange Cash',
                    'bank_wallet': 'admin_bank_wallet'.tr,
                  }.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _issuer = v ?? _issuer),
              ),
            ),
            _field('msisdn', label: 'admin_wallet_number_01'.tr, keyboard: TextInputType.phone, ltr: true, required: true),
          ] else ...[
            _field('bank_code', label: 'admin_bank_code_e_g_cib'.tr, ltr: true, required: true),
            _field('bank_card_number', label: 'admin_account_number_iban'.tr, ltr: true, required: true),
          ],
          _field('account_name', label: 'account_holder_full_name_hint'.tr, required: true),
          _field('national_id', keyboard: TextInputType.number, ltr: true),
        ];
      default:
        final server = _serverFields(p);
        if (server.isNotEmpty) {
          return [
            for (final f in server)
              _field(
                f.key,
                label: f.key == 'swift_code' && f.required ? 't2_pay_swift_req'.tr : null,
                ltr: f.key != 'account_name' && f.key != 'bank_name' && f.key != 'city',
                required: f.required,
                helper: f.key == 'account_name' ? 't2_pay_name_hint'.tr : null,
              ),
          ];
        }
        return [
          _field('account_name', required: true, helper: 't2_pay_name_hint'.tr),
          _field('bank_name', required: true),
          _field('iban', ltr: true, required: true),
          _field('swift_code', ltr: true),
        ];
    }
  }

  List<String> _required(TeacherPayoutProvider p) {
    switch (_method) {
      case 'instapay':
        return ['account_name', 'instapay_id'];
      case 'moyasar':
        return ['account_name', 'iban'];
      case 'paymob':
        return _paymobKind == 'wallet' ? ['account_name', 'msisdn'] : ['account_name', 'bank_code', 'bank_card_number'];
      default:
        final server = _serverFields(p);
        if (server.isNotEmpty) return [for (final f in server) if (f.required) f.key];
        return ['bank_name', 'account_name', 'iban'];
    }
  }

  Future<void> _save(TeacherPayoutProvider p) async {
    final need = _required(p);
    for (final k in need) {
      if ((_ctrls[k]?.text.trim() ?? '').isEmpty) {
        toast('admin_fill_in_the_required_fields'.tr, error: true);
        return;
      }
    }
    final server = _serverFields(p);
    final keys = <String>{
      ...need,
      if (_method == 'bank_account') 'swift_code',
      if (_method == 'bank_account') ...[for (final f in server) f.key],
      if (_method == 'moyasar') ...['mobile', 'city'],
      if (_method == 'paymob') 'national_id',
    };
    final details = <String, dynamic>{
      for (final k in keys)
        if ((_ctrls[k]?.text.trim() ?? '').isNotEmpty) k: _ctrls[k]!.text.trim(),
      if (_method == 'paymob') 'kind': _paymobKind,
      if (_method == 'paymob' && _paymobKind == 'wallet') 'issuer': _issuer,
    };
    setState(() => _busy = true);
    final iban = details['iban'];
    if (iban is String && (_method == 'bank_account' || _method == 'moyasar')) {
      final check = await p.checkIban(iban);
      if (!mounted) return;
      if (check != null && check.code != null) {
        setState(() => _busy = false);
        final key = 'a2_${check.code}';
        toast(key.tr == key ? 'a2_iban_format'.tr : key.tr, error: true);
        return;
      }
      if (check?.iban != null) details['iban'] = check!.iban;
    }
    final ok = await p.saveAccount(
      id: widget.existing?.id,
      method: _method,
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      details: details,
      makeDefault: _makeDefault,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherPayoutProvider>();
    final methods = p.methods;
    final info = methods.where((m) => m.id == _method).firstOrNull;
    final pickMethod = widget.existing == null && methods.length > 1;
    return AppSheetContent(
      title: widget.existing == null ? 't2_pay_new_account'.tr : 'admin_edit_account'.tr,
      icon: Icons.account_balance_rounded,
      tone: AppTone.info,
      children: [
        if (pickMethod) ...[
          if (methods.length <= 3)
            AppTabs(
              expand: true,
              items: [for (final m in methods) AppTabItem(m.label)],
              index: methods.indexWhere((m) => m.id == _method).clamp(0, methods.length - 1),
              onChanged: (i) => setState(() => _method = methods[i].id),
            )
          else
            AppDropdown<String>(
              decoration: InputDecoration(labelText: 'admin_payout_method'.tr),
              value: _method,
              items: [for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.label))],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (info != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              info.automatic
                  ? trp('admin_automatic_transfer_in_after_admin', {'currency': info.currency})
                  : 'admin_manual_transfer_by_the_admin_after'.tr,
              style: AppType.meta(context),
            ),
          ),
        ..._fields(p),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppField(controller: _label, label: 'admin_nickname_optional'.tr),
        ),
        if (widget.existing == null)
          AppSwitchTile(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            title: 'admin_make_default'.tr,
            value: _makeDefault,
            onChanged: (v) => setState(() => _makeDefault = v),
          ),
        const SizedBox(height: AppSpace.sm),
        AppButtonRow(
          primary: AppButton.primary(label: 't2_pay_save_account'.tr, busy: _busy, onPressed: () => _save(p)),
          secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
        ),
      ],
    );
  }
}
