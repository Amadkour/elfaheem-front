// lib/features/shared/points/points_wallet_page.dart — the points wallet (docs/backend/live-rooms-spec.md §9,
// feature key `profile.points`): the live-meeting plan card, the balance with "Buy points", my top-ups with their
// status and the history (ledger kinds as text).
//
//   PointsWalletPage({openPlan})   the page; `openPlan` opens the plan sheet on arrival (the `live_plan` deep link)
//   PointsWalletView               the plain-values body (test/ui/points_layout_test.dart)
//   TopupForm                      "Buy points": amount (≥ topup_min, its money price), method, receipt → submit;
//                                  method "Card" (Part 3 §13) → POST /me/points/checkout → the provider's payment
//                                  page and the status sheet (points_card_checkout.dart)
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'live_plan_sheet.dart';
import 'points_api.dart';
import 'points_card_checkout.dart' show runCardTopup;

class PointsWalletPage extends StatefulWidget {
  const PointsWalletPage({super.key, this.openPlan = false, this.api = const PointsApi()});

  /// Open the live-meeting plan sheet as soon as the page is shown (`live_plan` deep link).
  final bool openPlan;
  final PointsApi api;

  @override
  State<PointsWalletPage> createState() => _PointsWalletPageState();
}

class _PointsWalletPageState extends State<PointsWalletPage> {
  PointsWallet? _wallet;
  LivePlan? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (widget.openPlan && mounted) await _openPlan();
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final plan = widget.api.livePlan().then<LivePlan?>((p) => p, onError: (_) => null); // a plan error never hides the wallet
    try {
      final w = await widget.api.wallet();
      final p = await plan;
      if (mounted) setState(() { _wallet = w; _plan = p; });
    } catch (e) {
      if (mounted) setState(() => _error = pointsErrorText(e));
    }
  }

  Future<void> _openPlan() async {
    await showLivePlanSheet(context, api: widget.api);
    if (mounted) await _load();
  }

  Future<void> _buy() async {
    final w = _wallet;
    if (w == null) return;
    final done = await showAppSheet<Object>(
        context,
        (ctx) => TopupForm(
              wallet: w,
              submit: (points, method, name, bytes) =>
                  widget.api.createTopup(points: points, method: method, fileName: name, bytes: bytes),
              checkout: (points) => widget.api.checkout(points: points),
            ));
    if (done == true) {
      appToast(t('أُرسل طلب الشحن، سيُضاف الرصيد بعد المراجعة', 'Top-up sent — the points are added after review'));
      if (mounted) await _load();
    } else if (done is PointsCheckout && mounted) {
      await runCardTopup(context, widget.api, done);
      if (mounted) await _load(); // the balance and the top-up's status, whatever the outcome
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey(kPointsFeatureKey),
        appBar: ScreenAppBar(title: t('محفظة النقاط', 'Points wallet')),
        child: AppRefresh(
          onRefresh: _load,
          child: PointsWalletView(
            wallet: _wallet,
            plan: _plan,
            nowUtc: DateTime.now().toUtc(),
            error: _error,
            onRetry: _load,
            onBuy: _buy,
            onOpenPlan: _openPlan,
          ),
        ),
      );
}

/// The wallet's body with plain values. [wallet] null = loading (with no [error]).
class PointsWalletView extends StatelessWidget {
  const PointsWalletView({
    super.key,
    required this.wallet,
    required this.nowUtc,
    this.plan,
    this.error,
    this.onRetry,
    this.onBuy,
    this.onOpenPlan,
  });

  final PointsWallet? wallet;
  final LivePlan? plan;
  final DateTime nowUtc;
  final String? error;
  final VoidCallback? onRetry, onBuy, onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = wallet;
    final p = plan;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (w == null && error == null)
          const AppListSkeleton(items: 5, withAvatar: false)
        else if (w == null)
          AppBanner(
              icon: Icons.error_outline_rounded,
              text: error!,
              color: c.danger,
              action: onRetry == null
                  ? null
                  : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)))
        else ...[
          if (p != null && p.needed) ...[
            LivePlanSummary(plan: p, nowUtc: nowUtc, onTap: onOpenPlan),
            const SizedBox(height: 12),
          ],
          PointsBalanceCard(wallet: w, onBuy: onBuy),
          if (error != null) ...[
            const SizedBox(height: 10),
            AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
          ],
          if (w.topups.isNotEmpty) ...[
            AppSectionTitle(t('طلبات الشحن', 'My top-ups'),
                subtitle: w.pendingTopups > 0 ? t('${w.pendingTopups} قيد المراجعة', '${w.pendingTopups} under review') : null),
            for (final x in w.topups) TopupTile(topup: x),
          ],
          AppSectionTitle(t('سجل النقاط', 'History')),
          if (w.history.isEmpty)
            AppEmpty(
                icon: Icons.receipt_long_rounded,
                title: t('لا حركات بعد', 'No activity yet'),
                message: t('تظهر هنا كل نقطة تُضاف أو تُصرف.', 'Every point added or spent shows here.'))
          else
            for (final e in w.history) LedgerTile(entry: e),
        ],
      ],
    );
  }
}

class PointsBalanceCard extends StatelessWidget {
  const PointsBalanceCard({super.key, required this.wallet, this.onBuy});

  final PointsWallet wallet;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = wallet;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.account_balance_wallet_rounded, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('رصيدك', 'Your balance'), style: appText(12, c: c.textLight)),
              Text('${w.balance} ${t('نقطة', 'points')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(24, w: FontWeight.w800, c: c.textDark)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          t('النقطة = ${moneyText(w.pricePerPoint, w.currency)} · أقل شحن ${w.topupMin} نقطة',
              '1 point = ${moneyText(w.pricePerPoint, w.currency)} · minimum top-up ${w.topupMin} points'),
          style: appText(12, c: c.textMedium),
        ),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('شراء نقاط', 'Buy points'), icon: Icons.add_card_rounded, onPressed: onBuy),
      ]),
    );
  }
}

Color topupStatusColor(BuildContext context, TopupStatus s) {
  final c = context.colors;
  return switch (s) {
    TopupStatus.pending => c.warning,
    TopupStatus.approved => c.success,
    TopupStatus.rejected => c.danger,
    TopupStatus.unknown => c.textLight,
  };
}

class TopupTile extends StatelessWidget {
  const TopupTile({super.key, required this.topup, this.trailing, this.showUser = false});

  final PointsTopup topup;
  final Widget? trailing;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = topup;
    final col = topupStatusColor(context, x.status);
    final when = x.createdAt == null ? '' : AppTime.dateTime(x.createdAt!);
    final user = x.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(x.isCard ? Icons.credit_card_rounded : Icons.add_card_rounded, color: col, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showUser && user != null)
                  Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                Text('${x.points} ${t('نقطة', 'points')} · ${x.amountText}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(showUser ? 13 : 14, w: FontWeight.w700, c: c.textDark)),
                Text([x.methodText, if (when.isNotEmpty) when].join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
                if (showUser && x.isCard && x.paymentId != null)
                  Text('${t('رقم العملية', 'Payment id')}: ${x.paymentId}',
                      key: ValueKey('topup.payment_id.${x.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: appText(12, c: c.textLight)),
                if (showUser && user != null && user.contact.isNotEmpty)
                  Text(user.contact, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
                if (x.note != null) Text(x.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
              ]),
            ),
            const SizedBox(width: 8),
            // a long status ("Waiting for payment") ellipsizes instead of pushing the amount off a phone
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: AppBadgePill(x.statusText, color: col)),
          ]),
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ]),
      ),
    );
  }
}

class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.entry});

  final PointsLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final col = e.delta >= 0 ? c.success : c.danger;
    final sub = [
      if (e.createdAt != null) AppTime.dateTime(e.createdAt!),
      if (e.note != null) e.note!,
      if (e.byName != null) e.byName!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: col.withValues(alpha: 0.12),
          child: Icon(e.delta >= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 18, color: col),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.kindText, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
            if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(e.deltaText, style: appText(15, w: FontWeight.w800, c: col)),
          Text('= ${e.balanceAfter}', style: appText(11, c: c.textLight)),
        ]),
      ]),
    );
  }
}

/// Sends a top-up (the multipart call); throws an API error the form shows.
typedef TopupSubmit = Future<Object?> Function(int points, String method, String fileName, Uint8List bytes);

/// "Buy points": amount (≥ topup_min, with its money price), method, receipt. Pops true once a transfer is sent;
/// with the method "Card" it calls [checkout] and pops the [PointsCheckout] (the caller opens the payment page).
class TopupForm extends StatefulWidget {
  const TopupForm({super.key, required this.wallet, required this.submit, this.pickReceipt, this.checkout});

  final PointsWallet wallet;
  final TopupSubmit submit;

  /// `POST /me/points/checkout` for the method "Card"; null hides nothing but refuses the card.
  final Future<PointsCheckout> Function(int points)? checkout;

  /// Test seam; null → the file picker (image or PDF).
  final Future<(String, Uint8List)?> Function()? pickReceipt;

  @override
  State<TopupForm> createState() => _TopupFormState();
}

class _TopupFormState extends State<TopupForm> {
  late final _points = TextEditingController(text: '${widget.wallet.topupMin}');
  late String? _method = widget.wallet.methods.isEmpty ? null : widget.wallet.methods.first;
  (String, Uint8List)? _receipt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  Future<(String, Uint8List)?> _pickFile() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    if (f == null) return null;
    try {
      return (f.name, await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> _pick() async {
    final r = await (widget.pickReceipt ?? _pickFile)();
    if (r == null || !mounted) return;
    if (r.$2.length > kReceiptMaxBytes) {
      setState(() => _error = pointsCodeText('receipt_too_large'));
      return;
    }
    setState(() {
      _receipt = r;
      _error = null;
    });
  }

  bool get _card => _method == 'card';

  Future<void> _payByCard(int? n) async {
    final err = topupAmountError(n, widget.wallet.topupMin) ?? (widget.checkout == null ? pointsCodeText('card_disabled') : null);
    if (err != null) return setState(() => _error = err);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await widget.checkout!(n!);
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = pointsErrorText(e); });
    }
  }

  Future<void> _send() async {
    final w = widget.wallet;
    final n = parsePoints(_points.text);
    if (_card) return _payByCard(n);
    final err = topupAmountError(n, w.topupMin) ??
        (_method == null ? pointsCodeText('invalid_method') : null) ??
        (_receipt == null ? pointsCodeText('receipt_required') : null);
    if (err != null) return setState(() => _error = err);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.submit(n!, _method!, _receipt!.$1, _receipt!.$2);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = pointsErrorText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget.wallet;
    final n = parsePoints(_points.text);
    final price = n == null || n <= 0 ? null : moneyText(w.priceOf(n), w.currency);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('شراء نقاط', 'Buy points')),
        AppNumberField(
          controller: _points,
          label: t('عدد النقاط', 'Points'),
          hint: t('أقل عدد ${w.topupMin}', 'At least ${w.topupMin}'),
          min: w.topupMin,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 8),
        AppBanner(
          icon: Icons.payments_rounded,
          color: c.primary,
          text: price == null
              ? t('النقطة = ${moneyText(w.pricePerPoint, w.currency)}', '1 point = ${moneyText(w.pricePerPoint, w.currency)}')
              : t('المبلغ المطلوب: $price', 'Amount to pay: $price'),
        ),
        const SizedBox(height: 12),
        AppDropdown<String>(
          value: _method,
          decoration: InputDecoration(labelText: t('طريقة الدفع', 'Payment method')),
          items: [for (final m in w.methods) DropdownMenuItem(value: m, child: Text(pointsMethodText(m)))],
          onChanged: _saving ? null : (v) => setState(() { _method = v; _error = null; }),
        ),
        const SizedBox(height: 12),
        if (_card)
          Text(
              t('ستنتقل إلى صفحة الدفع الآمنة لمزوّد الدفع؛ تُضاف النقاط فور تأكيد الدفع، دون إيصال أو مراجعة.',
                  "You go to the payment provider's secure page; the points are added as soon as the payment is confirmed, no receipt or review needed."),
              key: const ValueKey('topup_form.card_note'),
              style: appText(12, c: c.textLight, h: 1.4))
        else ...[
          OutlinedButton.icon(
            onPressed: _saving ? null : _pick,
            icon: Icon(_receipt == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                color: _receipt == null ? c.primary : c.success),
            label: Text(_receipt == null ? t('إرفاق إيصال الدفع (صورة أو PDF)', 'Attach the payment receipt (image or PDF)') : _receipt!.$1,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 6),
          Text(t('حوّل المبلغ ثم أرفق الإيصال؛ تُضاف النقاط بعد مراجعة الإدارة.',
                  'Transfer the amount, then attach the receipt; the points are added once the admin reviews it.'),
              style: appText(12, c: c.textLight, h: 1.4)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        const SizedBox(height: 16),
        if (_card)
          AppPrimaryButton(
              key: const ValueKey('topup_form.pay_card'),
              label: price == null ? t('ادفع بالبطاقة', 'Pay by card') : t('ادفع $price بالبطاقة', 'Pay $price by card'),
              icon: Icons.credit_card_rounded,
              busy: _saving,
              onPressed: _saving ? null : _send)
        else
          AppPrimaryButton(label: t('إرسال الطلب', 'Send request'), icon: Icons.send_rounded, busy: _saving, onPressed: _saving ? null : _send),
      ]),
    );
  }
}
