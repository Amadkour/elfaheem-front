// lib/features/payments/points/points_wallet_page.dart — the points wallet (docs/backend/live-rooms-spec.md §9,
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
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/live_plan_sheet.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart' show runCardTopup;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/learner/wardrobe.dart' show showWardrobe;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/features/rewards/my_rewards_page.dart';

class PointsWalletPage extends StatefulWidget {
  const PointsWalletPage({super.key, this.openPlan = false, this.api = const PointsApi(), this.games});

  /// Open the live-meeting plan sheet as soon as the page is shown (`live_plan` deep link).
  final bool openPlan;
  final PointsApi api;

  /// The games' coins (the second balance of the wallet, students only); null = `GamesV4Api()`.
  final GamesV4Api? games;

  @override
  State<PointsWalletPage> createState() => _PointsWalletPageState();
}

class _PointsWalletPageState extends State<PointsWalletPage> {
  PointsWallet? _wallet;
  LivePlan? _plan;
  int? _coins;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (widget.openPlan && mounted) await _openPlan();
    });
  }

  bool get _student => sdRoleOf(context) == null;

  Future<void> _load() async {
    setState(() { _error = null; _offline = false; });
    final plan = widget.api.livePlan().then<LivePlan?>((p) => p, onError: (_) => null); // a plan error never hides the wallet
    // the coins are a student's games balance; an error only hides the coins tile
    final coins = _student
        ? (widget.games ?? GamesV4Api()).profile().then<int?>((p) => p.coins, onError: (_) => null)
        : Future<int?>.value(null);
    try {
      final w = await widget.api.wallet();
      final p = await plan;
      final k = await coins;
      if (mounted) setState(() { _wallet = w; _plan = p; _coins = k; });
    } catch (e) {
      if (mounted) setState(() { _error = pointsErrorText(e); _offline = isConnectionFailure(e); });
    }
  }

  Future<void> _openPlan() async {
    await showLivePlanSheet(context, api: widget.api);
    if (mounted) await _load();
  }

  Future<void> _buy() async {
    final w = _wallet;
    if (w == null || offlineBlocked()) return; // points are never bought on the device (D-1351)
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

  void _help() => showAppSheet<void>(context, (ctx) => WalletHelpSheet(wallet: _wallet));

  @override
  Widget build(BuildContext context) {
    final student = _student;
    return SdArea(
      area: AppArea.money,
      child: BasePage(
        key: const ValueKey(kPointsFeatureKey),
        appBar: ScreenAppBar(
          title: 'sd_wallet_title'.tr,
          actions: [AppIconButton(icon: Icons.help_outline_rounded, tooltip: 'sd_wallet_help_title'.tr, onPressed: _help)],
        ),
        child: AppRefresh(
          onRefresh: _load,
          child: PointsWalletView(
            wallet: _wallet,
            plan: _plan,
            coins: student ? _coins : null,
            nowUtc: DateTime.now().toUtc(),
            error: _error,
            offline: _offline,
            onRetry: _load,
            onBuy: _buy,
            onOpenPlan: _openPlan,
            onWardrobe: student ? () => showWardrobe(context, api: widget.games) : null,
            onCoupons: student
                ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyRewardsPage()))
                : null,
          ),
        ),
      ),
    );
  }
}

/// The wallet's body with plain values. [wallet] null = loading (with no [error]).
///
/// Layout (Stu2Money `screen=wallet`): the hero ("محفظتي"), the balance card riding up over it (points, and the
/// games' coins for a student), ONE forward button "اشحن نقاط", the wardrobe and coupons links, the live-meeting plan,
/// my top-ups, and the history card with its All / In / Out pill.
class PointsWalletView extends StatelessWidget {
  const PointsWalletView({
    super.key,
    required this.wallet,
    required this.nowUtc,
    this.plan,
    this.coins,
    this.error,
    this.offline = false,
    this.onRetry,
    this.onBuy,
    this.onOpenPlan,
    this.onWardrobe,
    this.onCoupons,
  });

  final PointsWallet? wallet;
  final LivePlan? plan;

  /// The games' coins; null hides the coins tile (not a student, or the games did not answer).
  final int? coins;
  final DateTime nowUtc;
  final String? error;

  /// [error] is the connection's (QA_PHASE7 W-4): with no wallet yet, "needs a connection" instead of the error.
  final bool offline;
  final VoidCallback? onRetry, onBuy, onOpenPlan, onWardrobe, onCoupons;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final p = plan;
    final hero = AppHero(title: 'sd_wallet_title'.tr, subtitle: 'sd_wallet_sub'.tr, icon: Icons.account_balance_wallet_outlined);
    final Widget first;
    if (w == null && error == null) {
      first = const AppCard(child: AppListSkeleton(items: 3, withAvatar: false));
    } else if (w == null && offline) {
      first = AppCard(child: AppNeedsConnection(onRetry: onRetry));
    } else if (w == null) {
      first = AppCard(child: AppErrorState(message: error, onRetry: onRetry));
    } else {
      first = PointsBalanceCard(wallet: w, coins: coins, onBuy: onBuy, onWardrobe: onWardrobe, onCoupons: onCoupons);
    }
    return SdHeroList(hero: hero, children: [
      first,
      if (w != null) ...[
        if (error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger),
        ],
        if (p != null && p.needed) ...[
          AppSpace.gapMd,
          LivePlanSummary(plan: p, nowUtc: nowUtc, onTap: onOpenPlan),
        ],
        if (w.topups.isNotEmpty)
          SdSection(
            title: t('طلبات الشحن', 'My top-ups'),
            trailing: w.pendingTopups > 0
                ? AppStatusBadge(
                    label: t('${w.pendingTopups} قيد المراجعة', '${w.pendingTopups} under review'), tone: AppTone.warning)
                : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final x in w.topups) TopupTile(topup: x)]),
          ),
        AppSpace.gapLg,
        WalletHistoryCard(history: w.history),
      ],
    ]);
  }
}

/// The balance card: the points tile (sun) and, for a student, the coins tile (mint), ONE forward button "اشحن نقاط",
/// then the wardrobe button and the coupons link.
class PointsBalanceCard extends StatelessWidget {
  const PointsBalanceCard({super.key, required this.wallet, this.coins, this.onBuy, this.onWardrobe, this.onCoupons});

  final PointsWallet wallet;
  final int? coins;
  final VoidCallback? onBuy, onWardrobe, onCoupons;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final kit = context.colors.kit;
    final points = _BalanceTile(
      key: const ValueKey('wallet.points'),
      tone: kit.accent(AppAccent.sun),
      icon: Icons.toll_rounded,
      value: w.balance,
      unit: 'sd_wallet_points_unit'.tr,
      caption: 'sd_wallet_points_use'.tr,
      memoryKey: 'points.balance',
    );
    final coinTile = coins == null
        ? null
        : _BalanceTile(
            key: const ValueKey('wallet.coins'),
            tone: kit.accent(AppAccent.mint),
            icon: Icons.star_outline_rounded,
            value: coins!,
            unit: 'sd_wallet_coins_unit'.tr,
            caption: 'sd_wallet_coins_use'.tr,
            memoryKey: 'games.coins',
          );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (coinTile == null)
          points
        else
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: points),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: coinTile),
            ]),
          ),
        const SizedBox(height: AppSpace.xs),
        Text(
          t('النقطة = ${moneyText(w.pricePerPoint, w.currency)} · أقل شحن ${w.topupMin} نقطة',
              '1 point = ${moneyText(w.pricePerPoint, w.currency)} · minimum top-up ${w.topupMin} points'),
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.md),
        AppButton.hot(
          key: const ValueKey('wallet.buy'),
          label: 'sd_wallet_buy'.tr,
          icon: Icons.add_rounded,
          expand: true,
          size: AppButtonSize.lg,
          onPressed: onBuy,
        ),
        if (onWardrobe != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppButton.secondary(label: 'sd_wallet_wardrobe'.tr, expand: true, onPressed: onWardrobe),
        ],
        if (onCoupons != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppTile(
            dense: true,
            icon: Icons.confirmation_number_outlined,
            tone: kit.accent(AppAccent.pink),
            title: 'sd_wallet_coupons'.tr,
            trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textLight),
            onTap: onCoupons,
          ),
        ],
      ]),
    );
  }
}

/// One balance: a tinted tile with its icon, the figure rolling to its value (M10) and what it buys.
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    super.key,
    required this.tone,
    required this.icon,
    required this.value,
    required this.unit,
    required this.caption,
    required this.memoryKey,
  });

  final KitTone tone;
  final IconData icon;
  final int value;
  final String unit, caption, memoryKey;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    return Semantics(
      label: '$value $unit, $caption',
      excludeSemantics: true,
      child: AppCard(
        variant: AppCardVariant.tint,
        tone: tone,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppIconBox(icon: icon, tone: tone, solid: true),
          const SizedBox(height: AppSpace.sm),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, children: [
            AppOdometer('$value', memoryKey: memoryKey, style: AppType.statFigure(context, wide: wide)),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Text(unit, style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: tone.ink)),
        ]),
      ),
    );
  }
}

/// "وش الفرق؟": points, coins, ranking points and coupons in four rows, one "فهمت".
class WalletHelpSheet extends StatelessWidget {
  const WalletHelpSheet({super.key, this.wallet});

  final PointsWallet? wallet;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final w = wallet;
    final price = w == null ? '' : ' ${t('النقطة = ${moneyText(w.pricePerPoint, w.currency)}', '1 point = ${moneyText(w.pricePerPoint, w.currency)}')}';
    final rows = [
      (Icons.toll_rounded, kit.accent(AppAccent.sun), 'sd_wallet_help_points'.tr, '${'sd_wallet_help_points_d'.tr}$price'),
      (Icons.star_outline_rounded, kit.accent(AppAccent.mint), 'sd_wallet_help_coins'.tr, 'sd_wallet_help_coins_d'.tr),
      (Icons.emoji_events_outlined, kit.accent(AppAccent.grape), 'sd_wallet_help_rank'.tr, 'sd_wallet_help_rank_d'.tr),
      (Icons.confirmation_number_outlined, kit.accent(AppAccent.pink), 'sd_wallet_help_coupons'.tr, 'sd_wallet_help_coupons_d'.tr),
    ];
    return AppSheetContent(
      title: 'sd_wallet_help_title'.tr,
      children: [
        for (final (icon, tone, title, sub) in rows) ...[
          AppTile(leading: AppIconBox(icon: icon, tone: tone, solid: true), title: title, subtitle: sub),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.sm),
        AppButton.primary(label: 'sd_got_it'.tr, expand: true, onPressed: () => Navigator.of(context).maybePop()),
      ],
    );
  }
}

/// The history card: "حركات النقاط" with an All / In / Out pill and the rows parted by hairlines.
class WalletHistoryCard extends StatefulWidget {
  const WalletHistoryCard({super.key, required this.history});

  final List<PointsLedgerEntry> history;

  @override
  State<WalletHistoryCard> createState() => _WalletHistoryCardState();
}

class _WalletHistoryCardState extends State<WalletHistoryCard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = [
      for (final e in widget.history)
        if (_tab == 0 || (_tab == 1 && e.delta >= 0) || (_tab == 2 && e.delta < 0)) e,
    ];
    final tabs = AppTabs(
      hug: true,
      items: [AppTabItem('sd_all'.tr), AppTabItem('sd_wallet_in'.tr), AppTabItem('sd_wallet_out'.tr)],
      index: _tab,
      onChanged: (i) => setState(() => _tab = i),
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            Semantics(header: true, child: Text('sd_wallet_history'.tr, style: AppType.section(context))),
            if (widget.history.isNotEmpty) tabs,
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        if (rows.isEmpty)
          AppEmpty(
              icon: Icons.receipt_long_rounded,
              title: t('لا حركات بعد', 'No activity yet'),
              message: t('تظهر هنا كل نقطة تُضاف أو تُصرف.', 'Every point added or spent shows here.'))
        else
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.kit.line),
            LedgerTile(entry: rows[i]),
          ],
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

/// One move of the points history: an icon box by kind (in = the ok tone, out = the live tone), what it was, the
/// note and the date, and the signed amount with the balance after it. A row: the wallet draws the rows in one card,
/// the admin's history in a list.
class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.entry});

  final PointsLedgerEntry entry;

  static IconData iconOf(PointsLedgerEntry e) => switch (e.kind) {
        'grant' => Icons.card_giftcard_rounded,
        'topup' => Icons.add_rounded,
        'refund' => Icons.undo_rounded,
        'deduct' => Icons.remove_rounded,
        'spend' => e.refType == 'live_meeting' || e.refType == 'service_subscription'
            ? Icons.videocam_outlined
            : Icons.shopping_bag_outlined,
        _ => e.delta >= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final e = entry;
    final tone = e.delta >= 0 ? kit.ok : kit.live;
    final sub = [
      if (e.note != null) e.note!,
      if (e.byName != null) e.byName!,
      if (e.createdAt != null) AppTime.date(e.createdAt!),
    ].join((AppConfig.lang == 'ar' ? '، ' : ', '));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(children: [
          AppIconBox(icon: iconOf(e), tone: tone),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.kindText, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          AppSpace.gapXs,
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // signed figures read left to right in both languages ("−300", never "300−")
            Text(appDigits(e.deltaText),
                textDirection: TextDirection.ltr,
                style: AppType.figure(context).copyWith(color: tone.ink, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(appDigits('= ${e.balanceAfter}'),
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

  /// Four quick amounts: the minimum and its 2×, 4× and 10×.
  List<int> get _presets => [for (final k in const [1, 2, 4, 10]) widget.wallet.topupMin * k];

  void _preset(int n) => setState(() {
        _points.text = '$n';
        _error = null;
      });

  static IconData _methodIcon(String m) => switch (m) {
        'card' => Icons.credit_card_rounded,
        'bank_transfer' => Icons.account_balance_outlined,
        'instapay' || 'wallet' => Icons.phone_iphone_rounded,
        'cash' => Icons.payments_outlined,
        _ => Icons.payment_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final w = widget.wallet;
    final n = parsePoints(_points.text);
    final price = n == null || n <= 0 ? null : moneyText(w.priceOf(n), w.currency);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader('sd_wallet_buy'.tr),
        Text('sd_wallet_how_many'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= Breakpoints.mobile ? 4 : 2;
          final cell = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
          return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final p in _presets)
              SizedBox(
                width: cell,
                child: _PresetTile(
                  key: ValueKey('topup_form.preset.$p'),
                  points: p,
                  price: moneyText(w.priceOf(p), w.currency),
                  selected: n == p,
                  onTap: _saving ? null : () => _preset(p),
                ),
              ),
          ]);
        }),
        const SizedBox(height: AppSpace.sm),
        AppNumberField(
          controller: _points,
          label: 'sd_wallet_other_amount'.tr,
          hint: t('أقل عدد ${w.topupMin}', 'At least ${w.topupMin}'),
          min: w.topupMin,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: AppSpace.md),
        Text(t('طريقة الدفع', 'Payment method'), style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.sm),
        // the methods the server lists for this wallet (by country, RULES §3); one is chosen
        for (final m in w.methods) ...[
          AppTile(
            key: ValueKey('topup_form.method.$m'),
            dense: true,
            icon: _methodIcon(m),
            title: pointsMethodText(m),
            selected: _method == m,
            trailing: Icon(_method == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: _method == m ? set.ink : c.textLight),
            onTap: _saving ? null : () => setState(() { _method = m; _error = null; }),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.xs),
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
          AppButton.hot(
              expand: true,
              size: AppButtonSize.lg,
              key: const ValueKey('topup_form.pay_card'),
              label: price == null ? t('ادفع بالبطاقة', 'Pay by card') : 'sd_pay_amount'.tr.replaceAll('{amount}', price),
              busy: _saving,
              onPressed: _saving ? null : _send)
        else
          AppButton.hot(
              expand: true,
              size: AppButtonSize.lg,
              label: t('إرسال الطلب', 'Send request'),
              icon: Icons.send_rounded,
              busy: _saving,
              onPressed: _saving ? null : _send),
      ]),
    );
  }
}

/// A quick amount: "500 نقطة" over its price; the chosen one is the area's ink with the gold price.
class _PresetTile extends StatelessWidget {
  const _PresetTile({super.key, required this.points, required this.price, required this.selected, this.onTap});

  final int points;
  final String price;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final fg = selected ? c.onHero : c.textDark;
    return Semantics(
      button: true,
      selected: selected,
      child: AppJelly(
        child: Material(
          color: selected ? c.kit.ink : c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            side: BorderSide(color: selected ? c.kit.ink : c.kit.line, width: AppBorder.strong),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${appDigits('$points')} ${'sd_wallet_points_unit'.tr}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppType.tileTitle(context).copyWith(color: fg)),
                  Text(price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppType.meta(context).copyWith(color: selected ? c.kit.warmOnDark : set.ink)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
