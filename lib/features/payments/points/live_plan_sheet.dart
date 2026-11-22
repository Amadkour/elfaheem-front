// lib/features/payments/points/live_plan_sheet.dart — the student live-meeting plan (docs/backend/live-rooms-spec.md §8).
//
//   showLivePlanSheet(context)   → true when the person is now covered (subscribed, or staff who never need it).
//                                  Used by the room's "Upgrade" (live agent), the calendar's 402 live_plan_required,
//                                  the wallet page's plan card and the `live_plan` deep link.
//   LivePlanView                 the plain-values body (price in points, days, free minutes, balance, status) —
//                                what test/ui/points_layout_test.dart pumps.
//
// Part 3: the daily free-time cap (§14: what is left today; a 402 `live_plan_required` with `reason: daily_limit`
// opens the sheet as "Today's free time is used up") and auto-renew (§15: the switch "Renew automatically from my
// points" → PUT /me/live-plan {auto_renew}; the days left).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart';

/// Shows the plan with Subscribe. Returns true once the person is covered. [reason] is the 402's `reason`
/// (`daily_limit` → the header says today's free time is used up).
Future<bool> showLivePlanSheet(BuildContext context, {PointsApi api = const PointsApi(), String? reason}) async =>
    await showAppSheet<bool>(context, (ctx) => LivePlanSheet(api: api, reason: reason)) ?? false;

class LivePlanSheet extends StatefulWidget {
  const LivePlanSheet({super.key, this.api = const PointsApi(), this.reason});

  final PointsApi api;
  final String? reason;

  @override
  State<LivePlanSheet> createState() => _LivePlanSheetState();
}

class _LivePlanSheetState extends State<LivePlanSheet> {
  LivePlan? _plan;
  String? _error;
  bool _busy = false, _insufficient = false, _renewBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.api.livePlan();
      if (!mounted) return;
      setState(() {
        _plan = p;
        _insufficient = _insufficient && !p.canAfford;
      });
    } catch (e) {
      if (mounted) setState(() => _error = pointsErrorText(e));
    }
  }

  Future<void> _subscribe() async {
    if (offlineBlocked()) return; // points are spent online only (D-1351)
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.api.subscribe();
      appToast(t('تم الاشتراك في باقة الاجتماعات المباشرة', 'You are now on the live-meeting plan'));
      if (!mounted) return;
      setState(() => _plan = p);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final code = pointsErrorCode(e);
      if (code == 'plan_not_needed') return Navigator.pop(context, true); // staff: unlimited already
      setState(() {
        _busy = false;
        if (code == 'points_insufficient') {
          final d = pointsErrorDetail(e);
          final bal = d['balance'];
          _insufficient = true;
          if (_plan != null && bal is num) _plan = _plan!.copyWith(balance: bal.toInt());
        } else {
          _error = pointsErrorText(e);
        }
      });
    }
  }

  Future<void> _setAutoRenew(bool on) async {
    final before = _plan;
    if (before == null) return;
    setState(() {
      _renewBusy = true;
      _error = null;
      _plan = before.copyWith(autoRenew: on);
    });
    try {
      final p = await widget.api.setAutoRenew(on);
      if (!mounted) return;
      setState(() {
        _plan = p;
        _renewBusy = false;
      });
      appToast(p.autoRenew
          ? t('سيتجدد الاشتراك تلقائياً من نقاطك', 'The plan will renew automatically from your points')
          : t('أُوقف التجديد التلقائي', 'Automatic renewal is off'));
    } catch (e) {
      if (mounted) setState(() { _plan = before; _renewBusy = false; _error = pointsErrorText(e); });
    }
  }

  Future<void> _wallet() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PointsWalletPage()));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(livePlanReasonText(widget.reason) ?? t('باقة الاجتماعات المباشرة', 'Live-meeting plan')),
          LivePlanView(
            plan: _plan,
            nowUtc: DateTime.now().toUtc(),
            error: _error,
            busy: _busy,
            insufficient: _insufficient,
            reason: widget.reason,
            autoRenewBusy: _renewBusy,
            onAutoRenew: _setAutoRenew,
            onSubscribe: _subscribe,
            onWallet: _wallet,
            onRetry: _load,
            onClose: () => Navigator.pop(context, _plan?.active == true || _plan?.needed == false),
          ),
        ]),
      );
}

/// The plan's body with plain values. [plan] null = loading (with no [error]).
class LivePlanView extends StatelessWidget {
  const LivePlanView({
    super.key,
    required this.plan,
    required this.nowUtc,
    this.error,
    this.busy = false,
    this.insufficient = false,
    this.onSubscribe,
    this.onWallet,
    this.onRetry,
    this.onClose,
    this.reason,
    this.onAutoRenew,
    this.autoRenewBusy = false,
  });

  final LivePlan? plan;
  final DateTime nowUtc;
  final String? error;
  final bool busy, insufficient;
  final VoidCallback? onSubscribe, onWallet, onRetry, onClose;

  /// The 402's `reason` that opened the sheet (`daily_limit`).
  final String? reason;

  /// The auto-renew switch (null hides it); [autoRenewBusy] while the PUT runs.
  final ValueChanged<bool>? onAutoRenew;
  final bool autoRenewBusy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    if (p == null) {
      return error == null
          ? const SizedBox(height: AppTouch.min * 4 + AppSpace.lg, child: AppListSkeleton(items: 3, withAvatar: false))
          : AppBanner(
              icon: Icons.error_outline_rounded,
              text: error!,
              color: c.danger,
              action: onRetry == null
                  ? null
                  : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)));
    }
    if (!p.needed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppBanner(icon: Icons.all_inclusive_rounded, text: pointsCodeText('plan_not_needed')!, color: c.success),
        if (onClose != null) ...[
          AppSpace.gapMd,
          AppButton.primary(expand: true, label: t('حسناً', 'OK'), icon: Icons.check_rounded, onPressed: onClose),
        ],
      ]);
    }
    final usedUp = reason == kDailyLimitReason || p.dailyUsedUp;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (usedUp && !p.active) ...[
        AppBanner(
          key: const ValueKey('live_plan.daily_used_up'),
          icon: Icons.today_rounded,
          color: c.warning,
          text: '${livePlanReasonText(kDailyLimitReason)}. ${t('اشترك لتبدأ اجتماعك الآن بلا حد، أو عد غداً.', 'Subscribe to start your meeting now without a limit, or come back tomorrow.')}',
        ),
        AppSpace.gapSm,
      ],
      LivePlanSummary(plan: p, nowUtc: nowUtc),
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        PlanFact(icon: Icons.stars_rounded, value: '${p.pricePoints}', label: t('نقطة', 'points')),
        PlanFact(icon: Icons.event_available_rounded, value: '${p.days}', label: t('يوماً', 'days')),
        PlanFact(icon: Icons.timer_outlined, value: '${p.freeMinutes}', label: t('دقيقة مجانية بدونها', 'free minutes without it')),
        if (p.hasDailyCap)
          PlanFact(
              key: const ValueKey('live_plan.daily_left'),
              icon: Icons.today_rounded,
              value: '${p.dailyLeft}/${p.dailyFreeMinutes}',
              label: t('دقيقة مجانية متبقية اليوم', 'free minutes left today'),
              color: p.dailyLeft > 0 ? c.primary : c.warning),
        PlanFact(
            icon: Icons.account_balance_wallet_rounded,
            value: '${p.balance}',
            label: t('رصيدك', 'your balance'),
            color: p.canAfford ? c.success : c.warning),
      ]),
      AppSpace.gapMd,
      Text(
        p.dailyFreeMinutes > 0
            ? t('بدون الباقة يكون كل اجتماع تنشئه مجانياً لأول ${p.freeMinutes} دقيقة من البث، وبحد ${p.dailyFreeMinutes} دقيقة مجانية في اليوم لكل اجتماعاتك، ثم يتوقف. مع الباقة تصبح اجتماعاتك بلا حد زمني لمدة ${p.days} يوماً.',
                'Without the plan each meeting you create is free for its first ${p.freeMinutes} live minutes, up to ${p.dailyFreeMinutes} free minutes a day over all your meetings, then it stops. With the plan your meetings have no time limit for ${p.days} days.')
            : t('بدون الباقة يكون كل اجتماع تنشئه مجانياً لأول ${p.freeMinutes} دقيقة من البث، ثم يتوقف. مع الباقة تصبح اجتماعاتك بلا حد زمني لمدة ${p.days} يوماً.',
                'Without the plan each meeting you create is free for its first ${p.freeMinutes} live minutes, then it stops. With the plan your meetings have no time limit for ${p.days} days.'),
        style: AppType.body(context),
      ),
      if (p.hasDailyCap) ...[
        AppSpace.gapXs,
        Text(dailyFreeLeftText(p.dailyLeft, p.dailyFreeMinutes),
            key: const ValueKey('live_plan.daily_left_text'),
            style: AppType.bodyStrong(context).copyWith(color: p.dailyLeft > 0 ? c.textDark : appInk(context, c.warning))),
      ],
      if (onAutoRenew != null) ...[
        AppSpace.gapXs,
        AppSwitchTile(
          key: const ValueKey('live_plan.auto_renew'),
          icon: Icons.autorenew_rounded,
          title: t('جدّد تلقائياً من نقاطي', 'Renew automatically from my points'),
          subtitle: t('عند انتهاء الباقة تُخصم ${p.pricePoints} نقطة لتمديدها ${p.days} يوماً، إن كفى رصيدك.',
              'When the plan ends, ${p.pricePoints} points renew it for ${p.days} days, if your balance covers it.'),
          value: p.autoRenew,
          onChanged: autoRenewBusy ? null : onAutoRenew,
        ),
      ],
      if (insufficient) ...[
        AppSpace.gapSm,
        AppBanner(
          icon: Icons.account_balance_wallet_outlined,
          color: c.warning,
          text: '${pointsCodeText('points_insufficient')}: ${t('ينقصك ${p.shortfall} نقطة', 'you need ${p.shortfall} more points')}',
          action: onWallet == null ? null : TextButton(onPressed: onWallet, child: Text(t('المحفظة', 'Wallet'))),
        ),
      ],
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      AppSpace.gapLg,
      if (insufficient && onWallet != null)
        AppButton.primary(expand: true, label: t('اشحن نقاطاً', 'Buy points'), icon: Icons.add_card_rounded, onPressed: onWallet)
      else
        AppButton.primary(
          expand: true,
          label: p.active
              ? t('مدّد ${p.days} يوماً · ${p.pricePoints} نقطة', 'Extend ${p.days} days · ${p.pricePoints} points')
              : t('اشترك · ${p.pricePoints} نقطة', 'Subscribe · ${p.pricePoints} points'),
          icon: Icons.workspace_premium_rounded,
          busy: busy,
          onPressed: busy ? null : onSubscribe,
        ),
      if (!insufficient && onWallet != null) ...[
        AppSpace.gapXs,
        AppButton.ghost(label: t('محفظة النقاط', 'Points wallet'), icon: Icons.account_balance_wallet_outlined, expand: true, onPressed: onWallet),
      ],
    ]);
  }
}

/// A small fact pill (icon · value · label) that wraps its text instead of overflowing on a phone: the input well
/// with a hairline, the icon in the fact's tone, the value as a tabular figure.
class PlanFact extends StatelessWidget {
  const PlanFact({super.key, required this.icon, required this.value, required this.label, this.color});

  final IconData icon;
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.md, AppSpace.xs),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.sm, color: appInk(context, col)),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              TextSpan(text: ' $label', style: AppType.meta(context)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

/// One line of status: "Active until … · N days left" or "Not subscribed" — a paper card; an active plan wears the
/// emerald mark (done / covered), a missing one the primary's.
class LivePlanSummary extends StatelessWidget {
  const LivePlanSummary({super.key, required this.plan, required this.nowUtc, this.onTap});

  final LivePlan plan;
  final DateTime nowUtc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final end = p.endsAt;
    final active = p.active || !p.needed;
    final title = !p.needed
        ? t('اجتماعاتك بلا حد زمني', 'Your meetings are unlimited')
        : p.active
            ? t('باقة الاجتماعات المباشرة مفعّلة', 'Live-meeting plan active')
            : t('غير مشترك في باقة الاجتماعات', 'No live-meeting plan');
    final sub = !p.needed
        ? null
        : p.active && end != null
            ? [
                '${t('حتى', 'Until')} ${AppTime.dateTime(end)}',
                planDaysLeftText(p.daysLeft(nowUtc)),
                if (p.autoRenew) t('يتجدد تلقائياً', 'Renews automatically'),
              ].join(' · ')
            : [
                t('${p.freeMinutes} دقيقة مجانية لكل اجتماع · ${p.pricePoints} نقطة لـ ${p.days} يوماً',
                    '${p.freeMinutes} free minutes per meeting · ${p.pricePoints} points for ${p.days} days'),
                if (p.hasDailyCap) dailyFreeLeftText(p.dailyLeft, p.dailyFreeMinutes),
              ].join(' · ');
    final col = active ? c.success : c.primary;
    return AppCard(
      padding: AppSpace.card,
      onTap: onTap,
      child: Row(children: [
        Container(
          width: AppIconSize.hero,
          height: AppIconSize.hero,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Icon(active ? Icons.verified_rounded : Icons.videocam_rounded, color: appInk(context, col), size: AppIconSize.md),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            if (sub != null) ...[
              const SizedBox(height: AppSpace.xxs / 2),
              Text(sub, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
        if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.lg),
      ]),
    );
  }
}
