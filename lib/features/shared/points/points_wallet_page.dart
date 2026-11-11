// lib/features/shared/points/points_wallet_page.dart — the points wallet (docs/backend/live-rooms-spec.md §9,
// feature key `profile.points`): the live-meeting plan card, the balance with "Buy points", my top-ups with their
// status and the history (ledger kinds as text).
//
//   PointsWalletPage({openPlan})   the page; `openPlan` opens the plan sheet on arrival (the `live_plan` deep link)
//   PointsWalletView               the plain-values body (test/ui/points_layout_test.dart): the balance is the page's
//                                  ONE block (peach, the hero lean) with the figure rolling (AppOdometer); the plan,
//                                  the top-ups and the history are paper — the history ONE card of hairline rows
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
import 'package:flutter_education_app/design/app_motion_kit.dart';
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
    return LayoutBuilder(builder: (context, box) {
      final side = AppSpace.gutter(box.maxWidth);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xl),
        children: [
          AppWidthBox(
            width: AppWidth.reading,
            gutters: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                PointsBalanceCard(wallet: w, onBuy: onBuy),
                if (error != null) ...[
                  AppSpace.gapSm,
                  AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
                ],
                if (p != null && p.needed) ...[
                  AppSpace.gapMd,
                  LivePlanSummary(plan: p, nowUtc: nowUtc, onTap: onOpenPlan),
                ],
                if (w.topups.isNotEmpty) ...[
                  _WalletHeading(t('طلبات الشحن', 'My top-ups'),
                      subtitle: w.pendingTopups > 0 ? t('${w.pendingTopups} قيد المراجعة', '${w.pendingTopups} under review') : null),
                  for (final x in w.topups) TopupTile(topup: x),
                ],
                _WalletHeading(t('سجل النقاط', 'History')),
                if (w.history.isEmpty)
                  AppEmpty(
                      icon: Icons.receipt_long_rounded,
                      title: t('لا حركات بعد', 'No activity yet'),
                      message: t('تظهر هنا كل نقطة تُضاف أو تُصرف.', 'Every point added or spent shows here.'))
                else
                  // one paper card, the moves parted by warm hairlines (not a row of floating lines on the canvas)
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < w.history.length; i++) ...[
                        if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                        LedgerTile(entry: w.history[i]),
                      ],
                    ]),
                  ),
              ],
            ]),
          ),
        ],
      );
    });
  }
}

/// A section heading of the wallet: the editorial section face, 32 above it, 12 under it (system.md §4).
class _WalletHeading extends StatelessWidget {
  const _WalletHeading(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: AppSpace.sectionHead,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ]),
      );
}

/// The balance: the wallet's one block (peach, the hero lean), the figure rolling to its value, the price of a point
/// and ONE "Buy points".
class PointsBalanceCard extends StatelessWidget {
  const PointsBalanceCard({super.key, required this.wallet, this.onBuy});

  final PointsWallet wallet;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    return RepaintBoundary(
      child: AppTilt(
        radius: AppRadius.block,
        maxTilt: 2.5,
        glare: true,
        child: AppBlock(
          tone: AppBlockTone.peach,
          hero: true,
          child: Builder(builder: (context) {
            final c = context.colors;
            final ink = AppBlock.colorsOf(context);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.account_balance_wallet_rounded, size: AppIconSize.md, color: ink.accentInk(c.primary)),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(t('رصيدك', 'Your balance'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink.muted)),
                ),
              ]),
              AppSpace.gapXs,
              Semantics(
                label: '${w.balance} ${t('نقطة', 'points')}',
                excludeSemantics: true,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpace.xs,
                  children: [
                    // the key figure at the display size: the sans with tabular digits, so the drum keeps its width
                    AppOdometer('${w.balance}',
                        memoryKey: 'points.balance',
                        style: AppType.figureLarge(context).copyWith(color: ink.ink, fontSize: AppType.display(context).fontSize, height: 1.1)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Text(t('نقطة', 'points'), style: AppType.section(context).copyWith(color: ink.ink)),
                    ),
                  ],
                ),
              ),
              AppSpace.gapXs,
              Text(
                t('النقطة = ${moneyText(w.pricePerPoint, w.currency)} · أقل شحن ${w.topupMin} نقطة',
                    '1 point = ${moneyText(w.pricePerPoint, w.currency)} · minimum top-up ${w.topupMin} points'),
                style: AppType.meta(context).copyWith(color: ink.muted),
              ),
              AppSpace.gapLg,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.primary(label: t('شراء نقاط', 'Buy points'), icon: Icons.add_card_rounded, onPressed: onBuy),
              ),
            ]);
          }),
        ),
      ),
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

/// The kit tone of a top-up's status (its badge).
AppTone topupStatusTone(TopupStatus s) => switch (s) {
      TopupStatus.pending => AppTone.warning,
      TopupStatus.approved => AppTone.success,
      TopupStatus.rejected => AppTone.danger,
      TopupStatus.unknown => AppTone.neutral,
    };

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
    final meta = AppType.meta(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: AppIconSize.hero,
              height: AppIconSize.hero,
              decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Icon(x.isCard ? Icons.credit_card_rounded : Icons.add_card_rounded, color: appInk(context, col), size: AppIconSize.md),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showUser && user != null)
                  Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                Text('${x.points} ${t('نقطة', 'points')} · ${x.amountText}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: showUser ? AppType.row(context) : AppType.bodyStrong(context)),
                Text([x.methodText, if (when.isNotEmpty) when].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: meta),
                if (showUser && x.isCard && x.paymentId != null)
                  Text('${t('رقم العملية', 'Payment id')}: ${x.paymentId}',
                      key: ValueKey('topup.payment_id.${x.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: meta),
                if (showUser && user != null && user.contact.isNotEmpty)
                  Text(user.contact, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                if (x.note != null) Text(x.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textMedium)),
              ]),
            ),
            AppSpace.gapXs,
            // a long status ("Waiting for payment") ellipsizes instead of pushing the amount off a phone
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTouch.min * 2 + AppSpace.xl),
              child: AppStatusBadge(label: x.statusText, tone: topupStatusTone(x.status)),
            ),
          ]),
          if (trailing != null) ...[AppSpace.gapXs, trailing!],
        ]),
      ),
    );
  }
}

/// One move of the points history: in (emerald) or out (danger) · what it was · when · the signed amount and the
/// balance after it. A row: the wallet draws the rows in one card, the admin's history in a list.
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(children: [
          Container(
            width: AppIconSize.xl,
            height: AppIconSize.xl,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(e.delta >= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: AppIconSize.sm, color: appInk(context, col)),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.kindText, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          AppSpace.gapXs,
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // signed figures read left to right in both languages ("−300", never "300−")
            Text(e.deltaText,
                textDirection: TextDirection.ltr,
                style: AppType.figure(context).copyWith(color: appInk(context, col), fontFeatures: const [FontFeature.tabularFigures()])),
            Text('= ${e.balanceAfter}',
                textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ]),
      ),
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
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('شراء نقاط', 'Buy points')),
        AppNumberField(
          controller: _points,
          label: t('عدد النقاط', 'Points'),
          hint: t('أقل عدد ${w.topupMin}', 'At least ${w.topupMin}'),
          min: w.topupMin,
          onChanged: (_) => setState(() => _error = null),
        ),
        AppSpace.gapXs,
        AppBanner(
          icon: Icons.payments_rounded,
          color: c.primary,
          text: price == null
              ? t('النقطة = ${moneyText(w.pricePerPoint, w.currency)}', '1 point = ${moneyText(w.pricePerPoint, w.currency)}')
              : t('المبلغ المطلوب: $price', 'Amount to pay: $price'),
        ),
        AppSpace.gapSm,
        AppDropdown<String>(
          value: _method,
          decoration: InputDecoration(labelText: t('طريقة الدفع', 'Payment method')),
          items: [for (final m in w.methods) DropdownMenuItem(value: m, child: Text(pointsMethodText(m)))],
          onChanged: _saving ? null : (v) => setState(() { _method = v; _error = null; }),
        ),
        AppSpace.gapSm,
        if (_card)
          Text(
              t('ستنتقل إلى صفحة الدفع الآمنة لمزوّد الدفع؛ تُضاف النقاط فور تأكيد الدفع، دون إيصال أو مراجعة.',
                  "You go to the payment provider's secure page; the points are added as soon as the payment is confirmed, no receipt or review needed."),
              key: const ValueKey('topup_form.card_note'),
              style: AppType.meta(context))
        else ...[
          AppButton.secondary(
            label: _receipt == null ? t('إرفاق إيصال الدفع (صورة أو PDF)', 'Attach the payment receipt (image or PDF)') : _receipt!.$1,
            icon: _receipt == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
            expand: true,
            onPressed: _saving ? null : _pick,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(t('حوّل المبلغ ثم أرفق الإيصال؛ تُضاف النقاط بعد مراجعة الإدارة.',
                  'Transfer the amount, then attach the receipt; the points are added once the admin reviews it.'),
              style: AppType.meta(context)),
        ],
        if (_error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        AppSpace.gapMd,
        if (_card)
          AppButton.primary(
              expand: true,
              key: const ValueKey('topup_form.pay_card'),
              label: price == null ? t('ادفع بالبطاقة', 'Pay by card') : t('ادفع $price بالبطاقة', 'Pay $price by card'),
              icon: Icons.credit_card_rounded,
              busy: _saving,
              onPressed: _saving ? null : _send)
        else
          AppButton.primary(expand: true, label: t('إرسال الطلب', 'Send request'), icon: Icons.send_rounded, busy: _saving, onPressed: _saving ? null : _send),
      ]),
    );
  }
}
