// lib/features/rewards/my_rewards_page.dart — My rewards (Games v3 §3.2, CONTRACT §7; a Profile item, help page
// `rewards.mine`; kill switches `rewards.coupons` and `rewards.referral`).
//
//   MyRewardsPage   GET /me/rewards once on open (it marks my new coupons seen: the `rewards` badge drops) and again
//                   on the live event `rewards`. [focusCouponId] opens on that coupon (a `reward_coupon`
//                   notification), [section] 'invite' scrolls to the invite card (`referral_qualified`).
//   MyRewardsView   the body with plain values (test/ui/rewards_layout_test.dart):
//                     coupons      Active · Used · Expired; each card: the value, the code (LTR, Copy), where it
//                                  works, why I got it, the date; "Use now" on an active one
//                     my wins      the last wins, one line each (the board, the day, the reward's state)
//                     invite card  my link (Share), joined / waiting, each tier's progress (AppFill), the share tiers
//                     how it works four short lines
//   MyRewardsTile   the Profile row, with the `rewards` badge (AttentionTabs.rewards)
//   openCouponUse   "Use now": copies the code and opens where it can be spent (the store, the teachers' packages,
//                   the home's courses)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
import 'package:flutter_education_app/design/app_share_sheet.dart' show showAppShareSheet, kShareLinksKey;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/games/champions/winner_sheet.dart' show winnerScopeLine;
import 'package:flutter_education_app/features/games/learner/coupon_unlock_card.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/rewards/rewards_api.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

String couponsCountText(int n) => countText(n,
    ar1: 'قسيمة واحدة', ar2: 'قسيمتان', arFew: '$n قسائم', arMany: '$n قسيمة', en1: '1 coupon', en: '$n coupons');

String friendsCountText(int n) => countText(n,
    ar1: 'صديق واحد', ar2: 'صديقان', arFew: '$n أصدقاء', arMany: '$n صديقاً', en1: '1 friend', en: '$n friends');

String opensCountText(int n) => countText(n,
    ar1: 'فتحة واحدة', ar2: 'فتحتان', arFew: '$n فتحات', arMany: '$n فتحة', en1: '1 open', en: '$n opens');

const List<String> kCouponSections = ['active', 'used', 'expired'];

/// "Use now": the code goes to the clipboard and the app opens where it can be spent.
Future<void> openCouponUse(Coupon c) async {
  await Clipboard.setData(ClipboardData(text: c.code));
  showAppNotice(t('نُسخ الرمز ${c.code}: الصقه عند الدفع', 'Code ${c.code} copied: paste it at checkout'));
  final tab = switch (c.targetType ?? c.appliesTo) {
    'store' => 'store',
    'package' => 'teachers',
    _ => 'home',
  };
  if (c.targetType == 'course' && c.targetId != null) {
    await AppNavigator.openCourse(c.targetId!);
    return;
  }
  navigatorKey.currentState?.popUntil((r) => r.isFirst);
  AppNavigator.requestedTab.value = null;
  AppNavigator.requestedTab.value = tab;
}

/// "Choose your course" on an unlocked coupon: any course goes where the coupon works (the catalogue); an allowed
/// list opens a sheet of those courses, and the pick opens that course with the code copied.
Future<void> chooseCouponCourse(BuildContext context, Coupon c) async {
  final ids = c.courseIds;
  if (ids == null || ids.isEmpty) return openCouponUse(c);
  final titles = <int, String>{};
  await Future.wait([
    for (final id in ids)
      Future(() async {
        try {
          final r = await ApiClient().get('/api/v1/courses/$id');
          final name = r is Map ? '${r['title'] ?? r['name'] ?? ''}'.trim() : '';
          titles[id] = name.isEmpty ? t('كورس رقم $id', 'Course #$id') : name;
        } catch (_) {
          titles[id] = t('كورس رقم $id', 'Course #$id');
        }
      }),
  ]);
  if (!context.mounted) return;
  final pick = await showAppSheet<int>(
    context,
    (ctx) => AppSheetContent(
      title: t('اختر كورسك', 'Choose your course'),
      icon: Icons.school_rounded,
      tone: AppTone.gold,
      children: [
        for (final id in ids) ...[
          AppCard(
            key: ValueKey('rewards.coupon.${c.id}.course.$id'),
            onTap: () => Navigator.of(ctx).pop(id),
            child: Row(children: [
              Expanded(child: Text(titles[id] ?? '', style: AppType.row(ctx))),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
      ],
    ),
  );
  if (pick == null) return;
  await Clipboard.setData(ClipboardData(text: c.code));
  showAppNotice(t('نُسخ الرمز ${c.code}: الصقه عند الدفع', 'Code ${c.code} copied: paste it at checkout'));
  await AppNavigator.openCourse(pick);
}

class MyRewardsPage extends StatefulWidget {
  const MyRewardsPage({super.key, this.api, this.focusCouponId, this.section});

  final RewardsApi? api;
  final int? focusCouponId;

  /// 'invite' = scroll to the invite card.
  final String? section;

  @override
  State<MyRewardsPage> createState() => _MyRewardsPageState();
}

class _MyRewardsPageState extends State<MyRewardsPage> {
  late final RewardsApi _api = widget.api ?? RewardsApi();
  MyRewards? _data;
  String? _error;
  bool _loading = true;
  int _tab = 0;
  StreamSubscription<LiveEvent>? _events;
  final _inviteKey = GlobalKey();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _load();
    _events = LiveEvents.instance.listen({LiveEvents.rewards}, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    try {
      final r = await _api.mine();
      if (!mounted) return;
      setState(() {
        _data = r;
        _loading = false;
        if (!_focused) _tab = _initialTab(r);
      });
      unawaited(AttentionService.instance.refresh(quiet: true)); // the server marked my new coupons seen
      _focus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_data == null) {
          _error = rewardsErrorText(e);
        } else if (!quiet) {
          showAppNotice(rewardsErrorText(e), error: true);
        }
      });
    }
  }

  int _initialTab(MyRewards r) {
    final id = widget.focusCouponId;
    if (id == null) return _tab;
    final c = r.coupons.where((c) => c.id == id).firstOrNull;
    if (c == null) return _tab;
    return kCouponSections.indexOf(c.sectionAt(DateTime.now().toUtc())).clamp(0, 2);
  }

  void _focus() {
    if (_focused) return;
    _focused = true;
    if (widget.section != 'invite') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _inviteKey.currentContext;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: AppMotion.of(ctx).slow, alignment: 0.1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('مكافآتي', 'My rewards'), helpPageId: 'rewards.mine'),
      child: SafeArea(
        child: d == null
            ? (_loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load))
            : MyRewardsView(
                data: d,
                tab: _tab,
                onTab: (i) => setState(() => _tab = i),
                focusCouponId: widget.focusCouponId,
                inviteKey: _inviteKey,
                now: DateTime.now().toUtc(),
                onUse: openCouponUse,
                onChooseCourse: (c) => chooseCouponCourse(context, c),
                onShare: (link) => showAppShareSheet(
                  context,
                  url: link,
                  title: t('ادعُ أصدقاءك إلى الفهيم', 'Invite your friends to Alfaheem'),
                  kind: t('دعوة', 'Invite'),
                  icon: Icons.person_add_alt_1_rounded,
                  hint: t('من يُنشئ حساباً من رابطك يُحسب لك بعد أن يلعب ويتعلم.', 'Whoever signs up from your link counts for you once they play and learn.'),
                ),
                onRefresh: () => _load(quiet: true),
              ),
      ),
    );
  }
}

class MyRewardsView extends StatelessWidget {
  const MyRewardsView({
    super.key,
    required this.data,
    required this.tab,
    required this.now,
    this.onTab,
    this.focusCouponId,
    this.inviteKey,
    this.onUse,
    this.onShare,
    this.onChooseCourse,
    this.fixedClock = false,
    this.onRefresh,
  });

  final MyRewards data;
  final int tab;
  final ValueChanged<int>? onTab;
  final int? focusCouponId;
  final Key? inviteKey;
  final DateTime now;
  final ValueChanged<Coupon>? onUse;
  final ValueChanged<String>? onShare;
  final ValueChanged<Coupon>? onChooseCourse;

  /// Tests and goldens: [now] stays still (the page passes the real clock and the unlock cards tick on their own).
  final bool fixedClock;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final couponsShown = data.couponsOn && !couponsOff();
    final referral = data.referralOn && !referralOff() ? data.referral : null;
    final shares = data.referralOn && !referralOff() ? data.shares : null;
    final sections = {for (final s in kCouponSections) s: <Coupon>[]};
    for (final c in data.coupons) {
      sections[c.sectionAt(now)]!.add(c);
    }
    final current = sections[kCouponSections[tab.clamp(0, 2)]]!;
    final children = <Widget>[
      if (couponsShown) ...[
        Text(t('قسائم الخصم', 'Discount coupons'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        AppTabs(
          items: [
            AppTabItem('${t('فعّالة', 'Active')} (${sections['active']!.length})'),
            AppTabItem('${t('مستخدمة', 'Used')} (${sections['used']!.length})'),
            AppTabItem('${t('منتهية', 'Expired')} (${sections['expired']!.length})'),
          ],
          index: tab.clamp(0, 2),
          onChanged: (i) => onTab?.call(i),
          expand: true,
        ),
        const SizedBox(height: AppSpace.sm),
        if (current.isEmpty)
          AppEmpty(
            key: ValueKey('rewards.coupons.empty.${kCouponSections[tab.clamp(0, 2)]}'),
            icon: Icons.local_offer_outlined,
            tone: AppBlockTone.gold,
            title: switch (tab) {
              0 => t('لا قسائم فعّالة الآن', 'No active coupons right now'),
              1 => t('لم تستخدم قسيمة بعد', 'You have not used a coupon yet'),
              _ => t('لا قسائم منتهية', 'No expired coupons'),
            },
            message: tab == 0 ? t('تصلك القسائم حين تفوز في الألعاب أو يتعلم أصدقاؤك من دعوتك.', 'Coupons come when you win in the games or friends you invite start learning.') : null,
          )
        else
          for (final c in current) ...[
            if (c.hasUnlock && c.sectionAt(now) == 'active')
              CouponUnlockCard(
                coupon: c,
                now: fixedClock ? now : null,
                onShare: referral == null || onShare == null ? null : () => onShare!(referral.link),
                onChooseCourse: onChooseCourse == null ? null : () => onChooseCourse!(c),
              )
            else
              CouponCard(coupon: c, now: now, focused: c.id == focusCouponId, onUse: onUse == null ? null : () => onUse!(c)),
            const SizedBox(height: AppSpace.xs),
          ],
        const SizedBox(height: AppSpace.lg),
      ],
      if (data.wins.isNotEmpty && !championsOff()) ...[
        Text(t('انتصاراتي', 'My wins'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        AppCard(
          key: const ValueKey('rewards.wins'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in data.wins.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                child: Row(children: [
                  Icon(Icons.emoji_events_rounded, size: AppIconSize.md, color: appToneColor(context, AppTone.gold)),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(championTitle(w), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                      Text(winnerScopeLine(w), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ]),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  _RewardStatus(status: w.rewardStatus),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      if (referral != null)
        InviteCard(key: inviteKey, referral: referral, shares: shares, onShare: onShare == null ? null : () => onShare!(referral.link)),
      if (referral != null) const SizedBox(height: AppSpace.lg),
      HowRewardsWork(coupons: couponsShown, referral: referral != null),
    ];
    final list = ListView(
      key: const ValueKey('rewards.mine'),
      padding: const EdgeInsets.all(AppSpace.md),
      children: [...children, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

class _RewardStatus extends StatelessWidget {
  const _RewardStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => switch (status) {
        'issued' => AppStatusBadge(label: t('قسيمة', 'Coupon'), tone: AppTone.success, dense: true),
        'pending' => AppStatusBadge(label: t('قيد المراجعة', 'Being checked'), tone: AppTone.warning, dense: true),
        'revoked' => AppStatusBadge(label: t('أُلغيت', 'Cancelled'), dense: true),
        _ => const SizedBox.shrink(),
      };
}

/// One coupon: the value, the code (always left-to-right, Copy), where it works, why I got it and its date.
class CouponCard extends StatelessWidget {
  const CouponCard({super.key, required this.coupon, required this.now, this.focused = false, this.onUse});

  final Coupon coupon;
  final DateTime now;
  final bool focused;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = coupon.sectionAt(now);
    final active = s == 'active';
    final date = switch (s) {
      'used' => coupon.redeemedAt == null ? t('استُخدمت', 'Used') : t('استُخدمت في ${AppTime.date(coupon.redeemedAt!)}', 'Used on ${AppTime.date(coupon.redeemedAt!)}'),
      'expired' => coupon.status == 'revoked'
          ? t('أُلغيت', 'Cancelled')
          : (coupon.expiresAt == null ? t('منتهية', 'Expired') : t('انتهت في ${AppTime.date(coupon.expiresAt!)}', 'Expired on ${AppTime.date(coupon.expiresAt!)}')),
      _ => coupon.expiresAt == null ? '' : t('صالحة حتى ${AppTime.date(coupon.expiresAt!)}', 'Valid until ${AppTime.date(coupon.expiresAt!)}'),
    };
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    return Container(
      key: ValueKey('rewards.coupon.${coupon.id}'),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: focused ? c.primary : c.divider, width: focused ? AppBorder.focus : AppBorder.hairline),
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: active ? gold.surface : c.background, shape: BoxShape.circle),
            child: Icon(Icons.local_offer_rounded, color: active ? gold.ink : c.textLight),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(coupon.valueText, style: AppType.section(context).copyWith(color: active ? null : c.textMedium)),
              const SizedBox(height: AppSpace.xxs),
              Text('${coupon.sourceText} · ${coupon.appliesText}', style: AppType.meta(context)),
              if (coupon.minOrder > 0)
                Text(t('على مشتريات من ${rewardsMoney(coupon.minOrder, coupon.currency)} فأكثر', 'On purchases of ${rewardsMoney(coupon.minOrder, coupon.currency)} or more'),
                    style: AppType.meta(context)),
              if (date.isNotEmpty) Text(date, style: AppType.meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(
            child: Semantics(
              label: t('رمز القسيمة ${coupon.code}', 'Coupon code ${coupon.code}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: AppRadius.controlAll,
                  border: Border.all(color: c.divider, width: AppBorder.hairline),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(coupon.code, maxLines: 1, style: AppType.bodyStrong(context).copyWith(letterSpacing: 1.5)),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          IconButton(
            key: ValueKey('rewards.coupon.${coupon.id}.copy'),
            tooltip: t('نسخ الرمز', 'Copy the code'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: coupon.code));
              showAppNotice(t('نُسخ الرمز', 'Code copied'));
            },
          ),
        ]),
        if (active && onUse != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppButton.primary(
            key: ValueKey('rewards.coupon.${coupon.id}.use'),
            label: t('استخدمها الآن', 'Use now'),
            icon: Icons.shopping_bag_rounded,
            expand: true,
            onPressed: onUse,
          ),
        ],
      ]),
    );
  }
}

/// The invite card: my link and Share, how many joined and wait, and each tier's progress.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.referral, this.shares, this.onShare});

  final ReferralInfo referral;
  final SharesInfo? shares;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = referral;
    final s = shares;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.person_add_alt_1_rounded, color: c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(t('ادعُ أصدقاءك', 'Invite your friends'), style: AppType.section(context))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(
          [
            t('انضم ${friendsCountText(r.qualified)}', '${friendsCountText(r.qualified)} joined'),
            if (r.pending > 0) t('${friendsCountText(r.pending)} في الانتظار', '${friendsCountText(r.pending)} waiting'),
          ].join(' · '),
          key: const ValueKey('rewards.invite.counts'),
          style: AppType.body(context),
        ),
        if (r.username != null)
          Text(t('أو يكتب صديقك اسمك @${r.username} عند التسجيل', 'Or your friend types @${r.username} when signing up'),
              style: AppType.meta(context)),
        const SizedBox(height: AppSpace.sm),
        for (final tier in r.tiers) ...[
          _TierRow(
            tier: tier,
            label: t('${tier.count} من ${friendsCountText(tier.threshold)}${tier.window == 'month' ? ' هذا الشهر' : ''}',
                '${tier.count} of ${friendsCountText(tier.threshold)}${tier.window == 'month' ? ' this month' : ''}'),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        if (s != null && s.tiers.isNotEmpty) ...[
          const Divider(height: AppSpace.md),
          Text(t('من فتح روابطك: ${opensCountText(s.uniqueOpens)}', 'People who opened your links: ${opensCountText(s.uniqueOpens)}'),
              style: AppType.body(context)),
          const SizedBox(height: AppSpace.xs),
          for (final tier in s.tiers) ...[
            _TierRow(
              tier: tier,
              label: t('${tier.count} من ${opensCountText(tier.threshold)}', '${tier.count} of ${opensCountText(tier.threshold)}'),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
        const SizedBox(height: AppSpace.xs),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(r.link, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ),
        const SizedBox(height: AppSpace.sm),
        if (onShare != null && !AppConfig.disableList.contains(kShareLinksKey))
          AppButton.primary(
            key: const ValueKey('rewards.invite.share'),
            label: t('شارك رابط الدعوة', 'Share your invite link'),
            icon: Icons.share_rounded,
            expand: true,
            onPressed: onShare,
          ),
      ]),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier, required this.label});

  final RewardTier tier;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$label, ${tier.rewardText}${tier.issued ? ', ${t('وصلتك', 'received')}' : ''}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tier.rewardText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
          const SizedBox(width: AppSpace.xs),
          if (tier.issued)
            AppStatusBadge(label: t('وصلتك', 'Received'), tone: AppTone.success, icon: Icons.check_rounded, dense: true)
          else
            Text(label, style: AppType.meta(context)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        AppFill(
          value: tier.issued ? 1 : tier.progress,
          builder: (context, v) => AppProgressBar(value: v * 100, color: tier.issued ? c.success : c.primary),
        ),
      ]),
    );
  }
}

/// Four short lines on how rewards work (modest, no promises).
class HowRewardsWork extends StatefulWidget {
  const HowRewardsWork({super.key, this.coupons = true, this.referral = true});

  final bool coupons, referral;

  @override
  State<HowRewardsWork> createState() => _HowRewardsWorkState();
}

class _HowRewardsWorkState extends State<HowRewardsWork> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = <(IconData, String)>[
      if (!championsOff())
        (Icons.emoji_events_rounded, t('أبطال اليوم والأسبوع في الألعاب قد يحصلون على قسيمة خصم.', 'The day\'s and the week\'s game champions may get a discount coupon.')),
      if (widget.referral)
        (Icons.person_add_alt_1_rounded, t('حين يسجّل صديق من رابطك ويتعلم فعلاً، يُحسب لك.', 'When a friend signs up from your link and really starts learning, it counts for you.')),
      if (widget.coupons) ...[
        (Icons.local_offer_rounded, t('القسيمة شخصية وتُستخدم مرة واحدة قبل تاريخ انتهائها.', 'A coupon is personal and works once, before it expires.')),
        (Icons.shopping_bag_rounded, t('اكتب الرمز أو اختر القسيمة عند الدفع: يُخصم قبل الرسوم والضريبة.', 'Type the code or pick the coupon at checkout: it comes off before fees and VAT.')),
      ],
    ];
    return AppExpandCard(
      expanded: _open,
      onExpandedChanged: (v) => setState(() => _open = v),
      header: Row(children: [
        Icon(Icons.help_outline_rounded, color: c.textMedium),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(t('كيف تعمل المكافآت', 'How it works'), style: AppType.section(context))),
      ]),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: AppIconSize.sm, color: c.primary),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(text, style: AppType.body(context))),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// The Profile row "My rewards", with the count of my new coupons.
class MyRewardsTile extends StatelessWidget implements AppSettingsSearchable {
  const MyRewardsTile({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  String get searchText => '${t('مكافآتي', 'My rewards')} rewards coupons discount invite referral مكافآت قسائم خصم دعوة';

  @override
  Widget build(BuildContext context) {
    if (GuestState.active || ViewAsState.active || rewardsOff()) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: AttentionService.instance,
      builder: (context, _) => AppSettingsTile(
        key: const ValueKey('rewards.entry'),
        icon: Icons.card_giftcard_rounded,
        color: context.colors.primary,
        label: t('مكافآتي', 'My rewards'),
        subtitle: t('قسائم الخصم ودعوة الأصدقاء', 'Discount coupons and inviting friends'),
        keywords: 'rewards coupons discount invite referral مكافآت قسائم خصم دعوة',
        badge: AttentionService.instance.count(AttentionTabs.rewards),
        onTap: onOpen,
      ),
    );
  }
}
